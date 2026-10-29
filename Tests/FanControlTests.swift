import Foundation

final class FakeHardware: FanHardware {
    var readings = [FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 0)]
    var cpu = [SensorReading(key: "Tp01", temperature: 50), SensorReading(key: "Tp05", temperature: 55)]
    var gpu = [SensorReading(key: "Tg0G", temperature: 45)]
    var commands: [(Int, Double)] = []
    var restores: [[Int]] = []
    var failWrite = false
    var failRestore = false
    var failRead = false
    func fans() throws -> [FanReading] { if failRead { throw FanError("read failed") }; return readings }
    func temperatures(_ keys: [String]) -> [SensorReading] { keys == FanSMC.cpuKeys ? cpu : gpu }
    func setFan(_ fan: FanReading, rpm: Double) throws {
        commands.append((fan.id, rpm))
        if failWrite { throw FanError("write rejected") }
    }
    func restore(_ ids: [Int]) throws {
        restores.append(ids)
        if failRestore { throw FanError("restore rejected") }
    }
}

@main struct Tests {
    static var count = 0
    static func check(_ label: String, _ body: () throws -> Void) rethrows {
        try body(); count += 1; print("PASS \(label)")
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String = "assertion failed", line: UInt = #line) {
        if !condition() { fatalError("\(message) at line \(line)") }
    }
    static func rejected(_ body: () throws -> Void) { do { try body(); fatalError("expected rejection") } catch {} }
    static func main() throws {
        check("background activity spans hidden-window control and releases exactly once") {
            var begins = 0, ends = 0
            var activity: FanControlActivity? = FanControlActivity(begin: { begins += 1; return NSObject() }, end: { _ in ends += 1 })
            activity?.setActive(false); require(begins == 0 && ends == 0)
            activity?.setActive(true); activity?.setActive(true)
            require(begins == 1 && ends == 0)
            activity?.setActive(false); activity?.setActive(false)
            require(ends == 1)
            activity?.setActive(true); activity = nil
            require(begins == 2 && ends == 2)
        }
        check("background fallback resumes the applied settings without unsaved edits") {
            var session = FanControlSession()
            var applied = FanConfiguration(); applied.mode = .curve
            session.applied(applied)
            var draft = applied; draft.points[0].temperature = 30
            let status = FanController(hardware: FakeHardware()).snapshot
            let now = Date()
            require(session.resumeConfiguration(for: status, now: now) == applied)
            require(session.resumeConfiguration(for: status, now: now) == nil)
            require(session.resumeConfiguration(for: status, now: now.addingTimeInterval(31)) == applied)
            require(applied != draft)
            session.didWake()
            require(session.resumeConfiguration(for: status, now: now) == applied)
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let owner = UUID()
            try! controller.configure(applied, client: owner, now: now)
            for seconds in stride(from: 2, through: 1800, by: 2) {
                let time = now.addingTimeInterval(Double(seconds))
                _ = controller.status(client: owner, now: time)
                controller.tick(now: time)
            }
            require(controller.snapshot.mode == .curve && hw.restores.isEmpty)
            let expired = now.addingTimeInterval(1815)
            controller.tick(now: expired)
            require(controller.snapshot.mode == .system && hw.restores == [[0]])
            session.didWake()
            let retry = session.resumeConfiguration(for: controller.snapshot, now: expired)
            require(retry == applied)
            try! controller.configure(retry!, client: owner, now: expired)
            require(controller.snapshot.mode == .curve)
        }
        check("temporary sensor errors preserve intent but block unsafe resumption") {
            var session = FanControlSession()
            var applied = FanConfiguration(); applied.mode = .manual; applied.manualRPM = 2300
            session.applied(applied)
            var status = FanController(hardware: FakeHardware()).snapshot
            status.error = "sensor failure"
            require(session.resumeConfiguration(for: status) == nil && session.configuration == applied)
            status.error = nil; status.cpu = []
            require(session.resumeConfiguration(for: status) == nil)
            status = FanController(hardware: FakeHardware()).snapshot
            status.fans = []
            require(session.resumeConfiguration(for: status) == nil)
            status = FanController(hardware: FakeHardware()).snapshot
            require(session.resumeConfiguration(for: status) == applied)
        }
        check("explicit system mode and release cancel retries; another controller is respected") {
            var session = FanControlSession()
            var applied = FanConfiguration(); applied.mode = .curve
            session.applied(applied)
            var status = FanController(hardware: FakeHardware()).snapshot
            status.fans = [FanReading(id: 0, actual: 2000, minimum: 1000, maximum: 4900, target: 2000, hardwareMode: 1)]
            require(session.resumeConfiguration(for: status) == nil)
            status = FanController(hardware: FakeHardware()).snapshot
            status.mode = .curve
            require(session.resumeConfiguration(for: status) == nil)
            session.stop(); session.didWake(); status.mode = .system
            require(session.resumeConfiguration(for: status) == nil)
            session.applied(applied); session.applied(FanConfiguration()); session.didWake()
            require(session.resumeConfiguration(for: status) == nil)
        }
        check("fan support is restricted to the existing M4 sensor family") {
            require(FanPlatform.supports(brand: "Apple M4"))
            require(FanPlatform.supports(brand: "Apple M4 Pro"))
            require(FanPlatform.supports(brand: "Apple M4 Max"))
            for brand in ["Apple M1", "Apple M3", "Apple M5", "Intel Core i7", "Apple M40", ""] {
                require(!FanPlatform.supports(brand: brand))
            }
        }
        check("languages translate UI, format values, and preserve Vietnamese") {
            require(FanLanguage.vietnamese.text("Áp dụng") == "Áp dụng")
            require(FanLanguage.english.text("Áp dụng") == "Apply")
            require(FanLanguage.chinese.text("Áp dụng") == "应用")
            require(FanLanguage.english.format("MỐC %d", 2) == "POINT 2")
            require(FanLanguage.chinese.format("Quạt %d: %d RPM", 1, 2000) == "风扇 1：2000 RPM")
            require(FanLanguage(rawValue: "zh-Hans") == .chinese)
        }
        check("helper and validation errors translate with dynamic details") {
            let message = "Đang thử trả quyền về macOS: Quạt 1 chưa trở về macOS."
            require(FanLanguage.english.message(message) == "Trying to return control to macOS: Fan 1 has not returned to macOS control.")
            require(FanLanguage.chinese.message("Không đọc được trạng thái quạt 2.") == "无法读取风扇 2 的状态。")
            require(FanLanguage.english.message("SMC F0Md từ chối lệnh (0x82).") == "SMC F0Md rejected the command (0x82).")
            require(FanLanguage.english.message("Nhiệt độ phải tăng dần và mức quạt không được giảm.") == "Temperatures must increase and fan levels must not decrease.")
        }
        let fan = FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 0)
        var config = FanConfiguration(); config.mode = .curve
        try check("curve endpoints and linear interpolation") {
            _ = try config.validated()
            require(config.fraction(at: 20) == 0)
            require(abs(config.fraction(at: 62.5) - 0.4) < 0.00001)
            require(config.fraction(at: 100) == 1)
        }
        check("invalid temperatures / descending curve / nonfinite rejected") {
            var invalid = config; invalid.points[1].temperature = 39; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[1].percent = -1; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[2].percent = 1; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points[3].percent = 99; rejected { _ = try invalid.validated() }
            invalid = config; invalid.manualRPM = .nan; rejected { _ = try invalid.validated() }
            invalid = config; invalid.points = []; rejected { _ = try invalid.validated() }
        }
        check("RPM clamping at hardware boundaries") {
            var policy = FanPolicy(); var manual = config; manual.mode = .manual; manual.manualRPM = 16000
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: nil) == 4900)
            policy.reset(); manual.manualRPM = 500
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: nil) == 1000)
        }
        check("CPU and GPU emergency override manual RPM") {
            var policy = FanPolicy(); var manual = config; manual.mode = .manual; manual.manualRPM = 1000
            require(policy.target(config: manual, fan: fan, cpu: 90, gpu: nil) == 4900)
            require(policy.target(config: manual, fan: fan, cpu: 50, gpu: 95) == 4900)
        }
        check("rising cooling immediate, declining cooling limited") {
            var policy = FanPolicy()
            require(policy.target(config: config, fan: fan, cpu: 40, gpu: nil) == 1000)
            require(policy.target(config: config, fan: fan, cpu: 90, gpu: nil) == 4900)
            require(policy.target(config: config, fan: fan, cpu: 40, gpu: nil) == 4750)
        }
        try check("SMC float / fixed-point codecs and signed temperature") {
            let float = FanSMCValue(type: "flt ", bytes: [0, 0, 0, 0])
            let encodedFloat = try float.encoding(2375); require(encodedFloat.number == 2375)
            let fixed = FanSMCValue(type: "fpe2", bytes: [0, 0])
            let encodedFixed = try fixed.encoding(4900); require(encodedFixed.number == 4900)
            require(FanSMCValue(type: "sp78", bytes: [255, 0]).number == -1)
            require(FanSMCValue(type: "flt ", bytes: [0]).number == nil)
            rejected { _ = try fixed.encoding(17000) }
        }
        try check("SMC waits for deferred takeover and release transitions") {
            var mode: Double = 0
            var pendingMode: Double = 0
            var target: Double = 1000
            var releasePolls = 0
            let smc = FanSMC(testTransport: { key, command, size, _, bytes in
                guard key == "F0Md" || key == "F0Tg" else { throw FanError("not found") }
                let type = key == "F0Md" ? "ui8 " : "flt "
                var packet = [UInt8](repeating: 0, count: 80)
                if command == 9 {
                    packet.withUnsafeMutableBytes {
                        $0.storeBytes(of: UInt32(key == "F0Md" ? 1 : 4), toByteOffset: 28, as: UInt32.self)
                        $0.storeBytes(of: type.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }, toByteOffset: 32, as: UInt32.self)
                    }
                } else if command == 6 {
                    require(size == bytes.count)
                    if key == "F0Md" { pendingMode = FanSMCValue(type: type, bytes: bytes).number! }
                    else { target = FanSMCValue(type: type, bytes: bytes).number!; if pendingMode != 0 || target != 0 { mode = pendingMode } }
                } else if command == 5 {
                    if key == "F0Md", pendingMode == 0, target == 0 {
                        releasePolls += 1
                        if releasePolls >= 3 { mode = 0 }
                    }
                    let value = try FanSMCValue(type: type, bytes: Array(repeating: 0, count: key == "F0Md" ? 1 : 4)).encoding(key == "F0Md" ? mode : target)
                    for (index, byte) in value.bytes.enumerated() { packet[48 + index] = byte }
                }
                return packet
            })
            try smc.setFan(fan, rpm: 2000)
            require(mode == 1 && target == 2000)
            try smc.restore([0])
            require(mode == 0 && target == 0 && releasePolls >= 3)
        }
        check("monitoring never writes hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            controller.tick(); _ = controller.status(client: UUID())
            require(hw.commands.isEmpty && hw.restores.isEmpty)
        }
        check("no fans or CPU data cannot start control") {
            for missingCPU in [true, false] {
                let hw = FakeHardware()
                if missingCPU { hw.cpu = [] } else { hw.readings = [] }
                let controller = FanController(hardware: hw)
                rejected { try controller.configure(config, client: UUID()) }
                require(hw.commands.isEmpty && hw.restores.isEmpty)
            }
        }
        try check("system mode releases active control and stops subsequent writes") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID()
            try controller.configure(config, client: client)
            var automatic = config; automatic.mode = .system
            try controller.configure(automatic, client: client)
            let writes = hw.commands.count
            controller.tick()
            require(hw.restores == [[0]] && hw.commands.count == writes && controller.snapshot.mode == .system)
        }
        try check("all fans use their own hardware limits and are restored together") {
            let hw = FakeHardware()
            hw.readings.append(FanReading(id: 1, actual: 1500, minimum: 1500, maximum: 6000, target: 1500, hardwareMode: 0))
            let controller = FanController(hardware: hw); let client = UUID()
            var manual = config; manual.mode = .manual; manual.manualRPM = 500
            try controller.configure(manual, client: client)
            require(hw.commands.count == 2 && hw.commands[0].1 == 1000 && hw.commands[1].1 == 1500)
            controller.disconnected(client)
            require(hw.restores == [[0, 1]])
        }
        try check("curve applies to hottest CPU sensor") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID())
            require(hw.commands.last!.1 == 1975)
            require(controller.snapshot.mode == .curve)
        }
        try check("watchdog returns to macOS without heartbeat") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let now = Date()
            try controller.configure(config, client: UUID(), now: now)
            controller.tick(now: now.addingTimeInterval(13))
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("owner heartbeat renews lease; other clients do not") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID(); let now = Date()
            try controller.configure(config, client: client, now: now)
            _ = controller.status(client: client, now: now.addingTimeInterval(10))
            controller.tick(now: now.addingTimeInterval(15)); require(hw.restores.isEmpty)
            _ = controller.status(client: UUID(), now: now.addingTimeInterval(22))
            controller.tick(now: now.addingTimeInterval(23)); require(hw.restores == [[0]])
        }
        try check("disconnect releases only the owning session") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID()
            try controller.configure(config, client: client)
            controller.disconnected(UUID()); require(hw.restores.isEmpty)
            controller.disconnected(client); require(hw.restores == [[0]])
        }
        try check("another client cannot replace active control") {
            let controller = FanController(hardware: FakeHardware())
            try controller.configure(config, client: UUID())
            rejected { try controller.configure(config, client: UUID()) }
        }
        try check("missing any discovered CPU sensor releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.cpu.removeLast(); controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.error != nil)
        }
        try check("missing GPU sensor releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.gpu = []; controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("fan read failure releases hardware") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw)
            try controller.configure(config, client: UUID()); hw.failRead = true; controller.tick()
            require(hw.restores == [[0]] && controller.snapshot.error != nil)
        }
        check("firmware write rejection rolls back takeover") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); hw.failWrite = true
            rejected { try controller.configure(config, client: UUID()) }
            require(hw.restores == [[0]] && controller.snapshot.mode == .system)
        }
        try check("failed restore retained and retried") {
            let hw = FakeHardware(); let controller = FanController(hardware: hw); let client = UUID()
            try controller.configure(config, client: client); hw.failRestore = true
            controller.disconnected(client); require(controller.snapshot.error != nil)
            hw.failRestore = false; controller.tick()
            require(hw.restores == [[0], [0]] && controller.snapshot.error == nil)
        }
        check("external fan controller prevents takeover") {
            let hw = FakeHardware(); hw.readings = [FanReading(id: 0, actual: 1000, minimum: 1000, maximum: 4900, target: 1000, hardwareMode: 1)]
            let controller = FanController(hardware: hw)
            rejected { try controller.configure(config, client: UUID()) }
            require(hw.commands.isEmpty && hw.restores.isEmpty)
        }
        try check("recovery journal persisted before write and removed after release") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            let hw = FakeHardware(); let controller = FanController(hardware: hw, journal: file); let client = UUID()
            try controller.configure(config, client: client)
            require(FileManager.default.fileExists(atPath: file.path))
            controller.disconnected(client)
            require(!FileManager.default.fileExists(atPath: file.path))
        }
        try check("daemon restart restores stale journal without reapplying curve") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try JSONEncoder().encode([0]).write(to: file)
            let hw = FakeHardware(); let controller = FanController(hardware: hw, journal: file)
            require(hw.restores == [[0]] && hw.commands.isEmpty && controller.snapshot.mode == .system)
        }
        print("\(count) behavioral tests passed.")
    }
}
