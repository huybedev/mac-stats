import Foundation

protocol FanHardware: AnyObject {
    func fans() throws -> [FanReading]
    func temperatures(_ keys: [String]) -> [SensorReading]
    func setFan(_ fan: FanReading, rpm: Double) throws
    func restore(_ ids: [Int]) throws
}
extension FanSMC: FanHardware {}

// All access is serialized on the helper's control queue.
final class FanController {
    let hardware: FanHardware
    var config = FanConfiguration()
    var snapshot = StatusSnapshot()
    private var policy = FanPolicy()
    private var owner: UUID?
    private var heartbeat: Date = .distantPast
    private var touched: Set<Int> = []
    private var expectedCPU: Set<String> = []
    private var expectedGPU: Set<String> = []
    private let journal: URL?

    init(hardware: FanHardware, journal: URL? = nil) {
        self.hardware = hardware
        self.journal = journal
        if let journal, let data = try? Data(contentsOf: journal), let ids = try? JSONDecoder().decode([Int].self, from: data) {
            touched = Set(ids.filter { (0...9).contains($0) })
            release(reason: "Đã phục hồi quyền macOS sau lần dừng trước.")
        }
        tick()
    }
    func status(client: UUID, now: Date = Date()) -> StatusSnapshot {
        if owner == client { heartbeat = now }
        return snapshot
    }
    func configure(_ newConfig: FanConfiguration, client: UUID, now: Date = Date()) throws {
        let value = try newConfig.validated()
        if let owner, owner != client { throw FanError("Một cửa sổ MacStats khác đang điều khiển quạt.") }
        if value.mode == .system { release(reason: "macOS đang quản lý quạt."); if let error = snapshot.error { throw FanError(error) }; return }
        guard touched.isEmpty || owner == client else { throw FanError("Đang phục hồi quyền macOS. Hãy thử lại sau.") }
        tick(now: now)
        guard snapshot.error == nil, snapshot.cpuTemperature != nil, !snapshot.fans.isEmpty else { throw FanError(snapshot.error ?? "Chưa đọc được cảm biến CPU.") }
        if owner == nil, snapshot.fans.contains(where: { $0.hardwareMode == 1 }) { throw FanError("Quạt đang ở chế độ thủ công của phần mềm khác. Hãy trả quạt về Auto trong phần mềm đó trước.") }
        expectedCPU = Set(snapshot.cpu.map(\.key))
        expectedGPU = Set(snapshot.gpu.map(\.key))
        // Persist recovery state before the first privileged hardware write.
        touched.formUnion(snapshot.fans.map(\.id))
        if let journal { try JSONEncoder().encode(Array(touched).sorted()).write(to: journal, options: .atomic) }
        owner = client
        heartbeat = now
        config = value
        policy.reset()
        tick(now: now)
        if let error = snapshot.error { throw FanError(error) }
    }
    func disconnected(_ client: UUID) { if owner == client { release(reason: "Ứng dụng đã ngắt kết nối; đã trả về macOS.") } }
    func release(reason: String) {
        config.mode = .system
        owner = nil
        policy.reset()
        snapshot.mode = .system
        snapshot.message = reason
        guard !touched.isEmpty else { snapshot.error = nil; return }
        do {
            try hardware.restore(Array(touched).sorted())
            touched.removeAll()
            if let journal { try? FileManager.default.removeItem(at: journal) }
            snapshot.error = nil
        } catch {
            snapshot.error = "Đang thử trả quyền về macOS: \(error.localizedDescription)"
        }
    }
    func tick(now: Date = Date()) {
        if owner == nil, !touched.isEmpty { release(reason: "Đã trả quyền điều khiển về macOS.") }
        if owner != nil, now.timeIntervalSince(heartbeat) > 12 { release(reason: "Ứng dụng không phản hồi; đã trả về macOS.") }
        do {
            snapshot.fans = try hardware.fans()
            snapshot.cpu = hardware.temperatures(FanSMC.cpuKeys)
            snapshot.gpu = hardware.temperatures(FanSMC.gpuKeys)
            snapshot.timestamp = now
            guard let cpu = snapshot.cpuTemperature else { throw FanError("Mất dữ liệu nhiệt độ CPU M4.") }
            if owner != nil {
                guard Set(snapshot.cpu.map(\.key)).isSuperset(of: expectedCPU), Set(snapshot.gpu.map(\.key)).isSuperset(of: expectedGPU),
                      Set(snapshot.fans.map(\.id)) == touched else { throw FanError("Mất cảm biến hoặc trạng thái quạt; đã dừng điều khiển.") }
                for fan in snapshot.fans {
                    let rpm = policy.target(config: config, fan: fan, cpu: cpu, gpu: snapshot.gpuTemperature)
                    try hardware.setFan(fan, rpm: rpm)
                }
                snapshot.fans = try hardware.fans()
                snapshot.mode = config.mode
                snapshot.message = max(cpu, snapshot.gpuTemperature ?? cpu) >= 90 ? "CPU/GPU ≥ 90°C: đang yêu cầu tốc độ tối đa." : config.mode.title
                snapshot.error = nil
            } else if touched.isEmpty {
                snapshot.error = nil
            }
        } catch {
            let cause = error.localizedDescription
            if !touched.isEmpty { release(reason: "Đã dừng điều khiển vì lỗi phần cứng.") }
            snapshot.error = [cause, snapshot.error].compactMap { $0 }.joined(separator: "\n")
        }
    }
}
