// AppleSMC packet layout and M4 key mapping informed by Stats (MIT).
// See FanControl/Resources/Stats-LICENSE.txt.
import Foundation
import IOKit

struct FanError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@available(macOS 14.0, *)
struct FanSMCValue {
    let type: String
    var bytes: [UInt8]
    var number: Double? {
        switch type {
        case "ui8 ": return bytes.first.map(Double.init)
        case "ui16": guard bytes.count >= 2 else { return nil }; return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32": guard bytes.count >= 4 else { return nil }; return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "flt ": guard bytes.count == 4 else { return nil }; return bytes.withUnsafeBytes { Double($0.loadUnaligned(as: Float.self)) }
        case "fpe2": guard bytes.count == 2 else { return nil }; return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78": guard bytes.count == 2 else { return nil }; return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default: return nil
        }
    }
    func encoding(_ number: Double) throws -> FanSMCValue {
        guard number.isFinite, number >= 0 else { throw FanError("Giá trị SMC không hợp lệ.") }
        var result = self
        switch type {
        case "flt ": var value = Float(number); result.bytes = withUnsafeBytes(of: &value, Array.init)
        case "fpe2": guard number <= 16383 else { throw FanError("RPM vượt giới hạn mã hóa.") }; let value = UInt16(number * 4); result.bytes = [UInt8(value >> 8), UInt8(value & 255)]
        case "ui8 ": guard number <= 255 else { throw FanError("Giá trị vượt giới hạn.") }; result.bytes = [UInt8(number)]
        default: throw FanError("Không hỗ trợ ghi kiểu SMC \(type).")
        }
        guard result.bytes.count == bytes.count else { throw FanError("Kích thước dữ liệu SMC sai.") }
        return result
    }
}

@available(macOS 14.0, *)
final class FanSMC {
    typealias Transport = (String, UInt8, Int, UInt32, [UInt8]) throws -> [UInt8]
    private var connection: io_connect_t = 0
    private var metadata: [String: (Int, String)] = [:]
    private var testTransport: Transport?
    init(testTransport: @escaping Transport) { self.testTransport = testTransport }
    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw FanError("Không tìm thấy AppleSMC.") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw FanError("Không mở được SMC: \(result).") }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    private func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private func fourCC(_ value: UInt32) -> String {
        String(bytes: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)], encoding: .ascii) ?? "????"
    }
    private func transact(key: String, command: UInt8, size: Int = 0, index: UInt32 = 0, bytes: [UInt8] = []) throws -> [UInt8] {
        guard key.utf8.count == 4, size <= 32, bytes.count <= 32 else { throw FanError("Gói SMC không hợp lệ.") }
        if let testTransport { return try testTransport(key, command, size, index, bytes) }
        // AppleSMC external method 2: 80 byte ABI, native-endian integer fields.
        var input = [UInt8](repeating: 0, count: 80)
        var output = input
        input.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: code(key), toByteOffset: 0, as: UInt32.self)
            raw.storeBytes(of: UInt32(size), toByteOffset: 28, as: UInt32.self)
            raw.storeBytes(of: index, toByteOffset: 44, as: UInt32.self)
        }
        input[42] = command
        for (index, value) in bytes.enumerated() { input[48 + index] = value }
        var outputSize = 80
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80 else { throw FanError("SMC \(key): IOKit \(String(format: "0x%08x", result)).") }
        guard output[40] == 0 else { throw FanError("SMC \(key) từ chối lệnh (\(String(format: "0x%02x", output[40]))).") }
        return output
    }
    func read(_ key: String) throws -> FanSMCValue {
        let info: (Int, String)
        if let cached = metadata[key] { info = cached }
        else {
            let packet = try transact(key: key, command: 9)
            info = packet.withUnsafeBytes { (Int($0.loadUnaligned(fromByteOffset: 28, as: UInt32.self)), fourCC($0.loadUnaligned(fromByteOffset: 32, as: UInt32.self))) }
            guard (1...32).contains(info.0) else { throw FanError("SMC \(key) không có dữ liệu.") }
            metadata[key] = info
        }
        let packet = try transact(key: key, command: 5, size: info.0)
        return FanSMCValue(type: info.1, bytes: Array(packet[48..<(48 + info.0)]))
    }
    func number(_ key: String) -> Double? { (try? read(key))?.number.flatMap { $0.isFinite ? $0 : nil } }
    private func write(_ key: String, number: Double) throws {
        let value = try read(key).encoding(number)
        _ = try transact(key: key, command: 6, size: value.bytes.count, bytes: value.bytes)
    }
    func modeKey(_ id: Int) -> String { (try? read("F\(id)md")) != nil ? "F\(id)md" : "F\(id)Md" }
    func fans() throws -> [FanReading] {
        guard let count = number("FNum"), (1...10).contains(count) else { throw FanError("Không đọc được số quạt.") }
        return try (0..<Int(count)).map { id in
            guard let actual = number("F\(id)Ac"), let minimum = number("F\(id)Mn"), let maximum = number("F\(id)Mx"),
                  actual >= 0, minimum >= 500, maximum > minimum, maximum <= 16000,
                  let mode = number(modeKey(id)) else { throw FanError("Không đọc được trạng thái quạt \(id + 1).") }
            return FanReading(id: id, actual: actual, minimum: minimum, maximum: maximum, target: number("F\(id)Tg"), hardwareMode: Int(mode))
        }
    }
    private var unlocked = false
    func setFan(_ fan: FanReading, rpm: Double) throws {
        let rpm = min(fan.maximum, max(fan.minimum, rpm))
        let key = modeKey(fan.id)
        if number(key) != 1 {
            do { try write(key, number: 1) }
            catch {
                guard (try? read("Ftst")) != nil else { throw error }
                unlocked = true // Restore even when firmware rejects a subsequent write.
                try write("Ftst", number: 1)
                var takeoverError: Error? = error
                for _ in 0..<50 {
                    usleep(100_000)
                    do { try write(key, number: 1); takeoverError = nil; break }
                    catch { takeoverError = error }
                }
                if let takeoverError { throw takeoverError }
            }
        }
        // Submit the complete mode+target command before polling state. Some
        // firmware only publishes the new mode once it has a nonzero target.
        try write("F\(fan.id)Tg", number: rpm)
        for _ in 0..<10 {
            usleep(100_000)
            if number(key) == 1, let actualTarget = number("F\(fan.id)Tg"), abs(actualTarget - rpm) <= 50 { return }
        }
        throw FanError("SMC chưa nhận điều khiển: mode=\(number(key).map { String(Int($0)) } ?? "?"); đích=\(number("F\(fan.id)Tg").map { String(Int($0)) } ?? "?") RPM; yêu cầu=\(Int(rpm)) RPM.")
    }
    func restore(_ ids: [Int]) throws {
        var errors: [String] = []
        for id in ids {
            do {
                try write(modeKey(id), number: 0)
                // A zero target releases the forced target on Apple Silicon.
                try write("F\(id)Tg", number: 0)
            } catch { errors.append(error.localizedDescription) }
        }
        if unlocked {
            do { try write("Ftst", number: 0); unlocked = false }
            catch { errors.append(error.localizedDescription) }
        }
        // Release is asynchronous too. Confirm the settled hardware state
        // before acknowledging success or scheduling another recovery attempt.
        var pending = ids
        for _ in 0..<10 {
            usleep(100_000)
            pending = pending.filter { id in
                guard let mode = number(modeKey(id)) else { return true }
                return mode != 0 && mode != 3
            }
            if pending.isEmpty { break }
        }
        for id in pending { errors.append("Quạt \(id + 1) chưa trở về macOS.") }
        guard errors.isEmpty else { throw FanError(errors.joined(separator: "\n")) }
    }
    static let cpuKeys = ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
    static let gpuKeys = ["Tg0G", "Tg0H", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
    func temperatures(_ keys: [String]) -> [SensorReading] {
        keys.compactMap { key in
            guard let value = number(key), (5...125).contains(value) else { return nil }
            return SensorReading(key: key, temperature: value)
        }
    }
}
