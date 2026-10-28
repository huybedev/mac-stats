import Foundation

let helperID = "com.openhoangnc.macstats.FanHelper"
@objc protocol FanServiceProtocol {
    func status(reply: @escaping (Data) -> Void)
    func configure(_ data: Data, reply: @escaping (Data) -> Void)
    func releaseControl(reply: @escaping (Data) -> Void)
}
struct SensorReading: Codable, Identifiable {
    var id: String { key }
    let key: String
    let temperature: Double
}
struct FanReading: Codable, Identifiable {
    let id: Int
    let actual: Double
    let minimum: Double
    let maximum: Double
    let target: Double?
    let hardwareMode: Int
}
enum ControlMode: String, Codable, CaseIterable {
    case system, curve, manual
    var title: String {
        switch self { case .system: return "macOS tự quản lý"; case .curve: return "Theo nhiệt độ CPU"; case .manual: return "RPM cố định" }
    }
}
struct CurvePoint: Codable, Identifiable, Equatable {
    var id: Double { temperature }
    var temperature: Double
    var percent: Double
}
struct FanConfiguration: Codable, Equatable {
    var mode: ControlMode = .system
    var points = [CurvePoint(temperature: 40, percent: 0), CurvePoint(temperature: 55, percent: 25), CurvePoint(temperature: 70, percent: 55), CurvePoint(temperature: 85, percent: 100)]
    var manualRPM: Double = 2000
    func validated() throws -> FanConfiguration {
        guard manualRPM.isFinite, (500...16000).contains(manualRPM), (2...8).contains(points.count) else { throw FanError("Cấu hình RPM không hợp lệ.") }
        for (index, point) in points.enumerated() {
            guard point.temperature.isFinite, point.percent.isFinite, (25...90).contains(point.temperature), (0...100).contains(point.percent) else { throw FanError("Nhiệt độ phải trong 25–90°C; mức quạt trong 0–100%.") }
            if index > 0 {
                guard point.temperature >= points[index - 1].temperature + 1, point.percent >= points[index - 1].percent else { throw FanError("Nhiệt độ phải tăng dần và mức quạt không được giảm.") }
            }
        }
        guard points.last!.percent == 100 else { throw FanError("Mốc cuối phải đạt 100%.") }
        return self
    }
    func fraction(at temperature: Double) -> Double {
        if temperature <= points[0].temperature { return points[0].percent / 100 }
        for index in 1..<points.count where temperature < points[index].temperature {
            let low = points[index - 1], high = points[index]
            return (low.percent + (high.percent - low.percent) * (temperature - low.temperature) / (high.temperature - low.temperature)) / 100
        }
        return points.last!.percent / 100
    }
}
struct StatusSnapshot: Codable {
    var cpu: [SensorReading] = []
    var gpu: [SensorReading] = []
    var fans: [FanReading] = []
    var mode: ControlMode = .system
    var message: String = "macOS đang quản lý quạt."
    var error: String?
    var timestamp = Date()
    var cpuTemperature: Double? { cpu.map(\.temperature).max() }
    var gpuTemperature: Double? { gpu.map(\.temperature).max() }
}
struct ServiceResponse: Codable {
    var status: StatusSnapshot?
    var error: String?
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

// Downward smoothing only: cooling demand rises immediately; falls gradually.
struct FanPolicy {
    private(set) var previous: [Int: Double] = [:]
    mutating func reset() { previous.removeAll() }
    mutating func target(config: FanConfiguration, fan: FanReading, cpu: Double, gpu: Double?) -> Double {
        let hottest = max(cpu, gpu ?? cpu)
        let requested: Double
        if hottest >= 90 { requested = fan.maximum }
        else if config.mode == .manual { requested = config.manualRPM }
        else { requested = fan.minimum + config.fraction(at: cpu) * (fan.maximum - fan.minimum) }
        let bounded = min(fan.maximum, max(fan.minimum, requested))
        let target = max(bounded, (previous[fan.id] ?? bounded) - 150)
        previous[fan.id] = target
        return target
    }
}
