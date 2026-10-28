import Foundation
import Security
import IOKit.pwr_mgt

private let controlQueue = DispatchQueue(label: "com.openhoangnc.macstats.fan.control")
private let support = URL(fileURLWithPath: "/Library/Application Support/MacStats/FanControl", isDirectory: true)

final class ClientSession: NSObject, FanServiceProtocol {
    let id = UUID()
    let controller: FanController
    init(_ controller: FanController) { self.controller = controller }
    func status(reply: @escaping (Data) -> Void) {
        controlQueue.async { reply(ServiceResponse(status: self.controller.status(client: self.id)).data) }
    }
    func configure(_ data: Data, reply: @escaping (Data) -> Void) {
        controlQueue.async {
            do {
                guard data.count <= 16384 else { throw FanError("Cấu hình quá lớn.") }
                let config = try JSONDecoder().decode(FanConfiguration.self, from: data)
                try self.controller.configure(config, client: self.id)
                reply(ServiceResponse(status: self.controller.snapshot).data)
            } catch { reply(ServiceResponse(status: self.controller.snapshot, error: error.localizedDescription).data) }
        }
    }
    func releaseControl(reply: @escaping (Data) -> Void) {
        controlQueue.async {
            self.controller.disconnected(self.id)
            reply(ServiceResponse(status: self.controller.snapshot, error: self.controller.snapshot.error).data)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    let controller: FanController
    let requirement: SecRequirement
    let requirementText: String
    init(controller: FanController) throws {
        self.controller = controller
        let text = try String(contentsOf: support.appendingPathComponent("client-requirement"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { throw FanError("Chữ ký ứng dụng không hợp lệ.") }
        self.requirement = requirement
        self.requirementText = text
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return false }
        let session = ClientSession(controller)
        connection.setCodeSigningRequirement(requirementText)
        connection.exportedInterface = NSXPCInterface(with: FanServiceProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { controlQueue.async { self.controller.disconnected(session.id) } }
        connection.interruptionHandler = { controlQueue.async { self.controller.disconnected(session.id) } }
        connection.resume()
        return true
    }
}

private var powerConnection: io_connect_t = 0
private var powerNotifier: io_object_t = 0
private var powerPort: IONotificationPortRef?
private var powerController: FanController?

@main struct HelperMain {
    static func main() {
        do { try run() }
        catch { fputs("MacStatsFanHelper: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        if CommandLine.arguments.contains("--probe") {
            let smc = try FanSMC()
            var snapshot = StatusSnapshot()
            snapshot.fans = try smc.fans()
            snapshot.cpu = smc.temperatures(FanSMC.cpuKeys)
            snapshot.gpu = smc.temperatures(FanSMC.gpuKeys)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(snapshot), encoding: .utf8)!)
            return
        }
        guard geteuid() == 0 else { throw FanError("Bộ trợ giúp cần chạy qua launchd với quyền quản trị.") }
        guard FanPlatform.isSupported else { throw FanError(FanPlatform.unsupportedMessage) }
        let controller = FanController(hardware: try FanSMC(), journal: support.appendingPathComponent("recovery.json"))
        let delegate = try HelperDelegate(controller: controller)
        let listener = NSXPCListener(machServiceName: helperID)
        listener.setConnectionCodeSigningRequirement(delegate.requirementText)
        listener.delegate = delegate
        listener.resume()
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { controller.tick() }
        timer.resume()
        var signals: [DispatchSourceSignal] = []
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: controlQueue)
            source.setEventHandler { controller.release(reason: "Bộ trợ giúp đang dừng."); exit(controller.snapshot.error == nil ? 0 : 1) }
            source.resume()
            signals.append(source)
        }
        powerController = controller
        powerConnection = IORegisterForSystemPower(nil, &powerPort, { _, _, message, argument in
            if message == 0xe0000280 { // kIOMessageSystemWillSleep (IOMessage.h)
                controlQueue.sync { powerController?.release(reason: "Máy đã ngủ; macOS đang quản lý quạt.") }
            }
            if message == 0xe0000280 || message == 0xe0000270 { // WillSleep / CanSystemSleep
                IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
            }
        }, &powerNotifier)
        guard powerConnection != 0, let powerPort else { throw FanError("Không đăng ký được thông báo ngủ/thức của máy.") }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(powerPort).takeUnretainedValue(), .defaultMode)
        withExtendedLifetime((delegate, listener, timer, signals)) { RunLoop.main.run() }
    }
}
