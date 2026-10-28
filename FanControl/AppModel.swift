import SwiftUI
import AppKit
import Security

struct TemperatureSample: Identifiable {
    let id = UUID()
    let date = Date()
    let cpu: Double
}

@available(macOS 14.0, *)
final class FanAppModel: ObservableObject {
    @Published var snapshot = StatusSnapshot()
    @Published var draft = FanConfiguration()
    @Published var connected = false
    @Published var busy = false
    @Published var error: String?
    @Published var history: [TemperatureSample] = []
    @Published var language = FanLanguage(rawValue: UserDefaults.standard.string(forKey: "fanControl.language") ?? "vi") ?? .vietnamese {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "fanControl.language") }
    }
    @Published var startCurve = UserDefaults.standard.bool(forKey: "fanControl.startCurve") {
        didSet { UserDefaults.standard.set(startCurve, forKey: "fanControl.startCurve") }
    }
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var inFlight = false
    private var requestedAt = Date.distantPast
    private var generation = UUID()
    private let readQueue = DispatchQueue(label: "com.openhoangnc.macstats.fan.read")
    private var localSMC: FanSMC?
    private var didAutoStart = false
    private var shuttingDown = false
    private var installingHelper = false
    var helperInstalled: Bool { FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/\(helperID).plist") }

    init() {
        draft.mode = .curve
        if let data = UserDefaults.standard.data(forKey: "fanControl.configuration"), let stored = try? JSONDecoder().decode(FanConfiguration.self, from: data), (try? stored.validated()) != nil { draft = stored }
        refresh()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func proxy() -> FanServiceProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: helperID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: FanServiceProtocol.self)
            var parsedRequirement: SecRequirement?
            // The helper is installed root-owned and its exact signature is bundled.
            guard let path = Bundle.main.path(forResource: "fan-helper-requirement", ofType: "txt"), let requirement = try? String(contentsOfFile: path, encoding: .utf8),
                  SecRequirementCreateWithString(requirement.trimmingCharacters(in: .whitespacesAndNewlines) as CFString, [], &parsedRequirement) == errSecSuccess else {
                error = "Tệp xác minh chữ ký helper không hợp lệ. Hãy cài lại ứng dụng."
                return nil
            }
            connection.setCodeSigningRequirement(requirement.trimmingCharacters(in: .whitespacesAndNewlines))
            let token = generation
            connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.lostConnection(token) } }
            connection.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.lostConnection(token) } }
            self.connection = connection
            connection.resume()
        }
        let token = generation
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] failure in
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.error = "Chưa kết nối được bộ trợ giúp. Hãy cài hoặc cập nhật bộ trợ giúp."
                self.lostConnection(token)
            }
        } as? FanServiceProtocol
    }
    private func lostConnection(_ token: UUID) {
        guard token == generation else { return }
        generation = UUID()
        let old = connection; connection = nil; old?.invalidate()
        connected = false
        inFlight = false
        busy = installingHelper
        if !shuttingDown, !installingHelper { readLocal() }
    }
    func refresh() {
        guard !shuttingDown, !installingHelper else { return }
        if inFlight {
            if Date().timeIntervalSince(requestedAt) > 8 { error = "Bộ trợ giúp không phản hồi; đang kết nối lại."; lostConnection(generation) }
            return
        }
        guard helperInstalled else { connected = false; readLocal(); return }
        guard let proxy = proxy() else { return }
        inFlight = true; requestedAt = Date()
        let token = generation
        proxy.status { [weak self] data in DispatchQueue.main.async {
            guard let self, token == self.generation else { return }
            self.inFlight = false
            self.receive(data)
            if self.connected, self.startCurve, !self.didAutoStart, !self.shuttingDown {
                self.didAutoStart = true
                self.draft.mode = .curve
                self.apply()
            }
        } }
    }
    private func readLocal() {
        guard !inFlight else { return }
        inFlight = true
        requestedAt = Date()
        let token = generation
        readQueue.async {
            var result = StatusSnapshot()
            do {
                if self.localSMC == nil { self.localSMC = try FanSMC() }
                guard let smc = self.localSMC else { return }
                result.fans = try smc.fans()
                result.cpu = smc.temperatures(FanSMC.cpuKeys)
                result.gpu = smc.temperatures(FanSMC.gpuKeys)
                result.message = "Chỉ theo dõi • Cài bộ trợ giúp để điều khiển quạt."
                if result.cpu.isEmpty { result.error = "Chưa đọc được cảm biến CPU M4." }
            } catch { result.error = error.localizedDescription; self.localSMC = nil }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.inFlight = false
                guard !self.connected else { return }
                self.update(result)
            }
        }
    }
    private func receive(_ data: Data) {
        guard let response = try? JSONDecoder().decode(ServiceResponse.self, from: data), response.status != nil else {
            error = "Phản hồi bộ trợ giúp không hợp lệ."
            lostConnection(generation)
            return
        }
        connected = true
        error = response.error
        if let status = response.status { update(status) }
    }
    private func update(_ value: StatusSnapshot) {
        snapshot = value
        if let temperature = value.cpuTemperature {
            history.append(TemperatureSample(cpu: temperature))
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }
    }
    func apply() {
        guard !busy, !shuttingDown else { return }
        do {
            let config = try draft.validated()
            guard connected, let proxy = proxy() else { throw FanError("Cài bộ trợ giúp trước khi điều khiển quạt.") }
            let data = try JSONEncoder().encode(config)
            busy = true; error = nil; inFlight = true; requestedAt = Date()
            let token = generation
            proxy.configure(data) { [weak self] response in DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.busy = false; self.inFlight = false; self.receive(response)
                if self.error == nil, self.snapshot.error == nil { UserDefaults.standard.set(data, forKey: "fanControl.configuration") }
            } }
        } catch { self.error = error.localizedDescription }
    }
    func prepareToQuit(completion: @escaping () -> Void) {
        shuttingDown = true
        timer?.invalidate()
        restore(completion: completion)
    }
    func restore(completion: (() -> Void)? = nil) {
        guard let connection else { completion?(); return }
        let token = generation
        var finished = false
        let finish: (Data?) -> Void = { [weak self] data in
            guard !finished else { return }
            finished = true
            if let self, token == self.generation {
                self.busy = self.installingHelper
                self.inFlight = false
                if let data {
                    self.receive(data)
                    if self.error == nil, self.snapshot.error == nil { self.draft.mode = .system }
                } else {
                    self.error = "Bộ trợ giúp không phản hồi; đang kết nối lại."
                    self.lostConnection(token)
                }
            }
            completion?()
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            DispatchQueue.main.async { finish(nil) }
        }) as? FanServiceProtocol else { finish(nil); return }
        busy = true; inFlight = true; requestedAt = Date()
        proxy.releaseControl { data in DispatchQueue.main.async { finish(data) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(nil) }
    }
    func installHelper(remove: Bool = false) {
        guard !busy, let script = Bundle.main.path(forResource: remove ? "uninstall-fan-helper" : "install-fan-helper", ofType: "sh") else { return }
        installingHelper = true
        busy = true; error = nil
        lostConnection(generation)
        let shellCommand = "/bin/bash " + shellQuote(script) + " " + shellQuote(Bundle.main.bundlePath)
        let prompt = language.text(remove ? "MacStats cần quyền quản trị để gỡ bộ điều khiển quạt." : "MacStats cần quyền quản trị để cài bộ điều khiển quạt.")
        let appleScript = "do shell script " + appleQuote(shellCommand) + " with administrator privileges with prompt " + appleQuote(prompt)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let errors = Pipe(); process.standardError = errors
            do {
                try process.run()
                let output = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.installingHelper = false
                    self.busy = false
                    self.lostConnection(self.generation)
                    if process.terminationStatus != 0 { self.error = String(data: output, encoding: .utf8) ?? "Thao tác chưa hoàn tất." }
                    else { self.error = nil; self.refresh() }
                }
            } catch { DispatchQueue.main.async { self.installingHelper = false; self.busy = false; self.error = error.localizedDescription } }
        }
    }
    func preset(_ kind: String) {
        draft.mode = .curve
        let temperatures: [Double] = kind == "Mát" ? [35, 50, 65, 80] : kind == "Êm" ? [45, 60, 75, 90] : [40, 55, 70, 85]
        draft.points = zip(temperatures, [0.0, 25, 55, 100]).map { CurvePoint(temperature: $0.0, percent: $0.1) }
    }
}

func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleQuote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
