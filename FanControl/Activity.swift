import Foundation

// Keep heartbeat delivery eligible while controlling fans, even with every
// window hidden. This activity explicitly allows the Mac itself to sleep.
final class FanControlActivity {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var token: NSObjectProtocol?

    init(begin: @escaping () -> NSObjectProtocol = {
        ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                             reason: "Maintain fan control heartbeat")
    }, end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.begin = begin
        self.end = end
    }

    func setActive(_ active: Bool) {
        if active, token == nil { token = begin() }
        if !active, let token { self.token = nil; end(token) }
    }

    deinit { if let token { end(token) } }
}

// Intent belongs to the running app, not to one XPC connection. Temporary
// watchdog/sleep/hardware fallback must not discard the user's applied mode.
struct FanControlSession {
    private(set) var configuration: FanConfiguration?
    private var nextAttempt = Date.distantPast

    mutating func applied(_ configuration: FanConfiguration) {
        self.configuration = configuration.mode == .system ? nil : configuration
        nextAttempt = .distantPast
    }
    mutating func stop() { configuration = nil; nextAttempt = .distantPast }
    mutating func didWake() { nextAttempt = .distantPast }
    mutating func retryLater(now: Date = Date()) { nextAttempt = now.addingTimeInterval(30) }

    mutating func resumeConfiguration(for status: StatusSnapshot, now: Date = Date()) -> FanConfiguration? {
        guard let configuration, status.mode == .system, status.error == nil,
              status.cpuTemperature != nil, !status.fans.isEmpty,
              status.fans.allSatisfy({ $0.hardwareMode != 1 }), now >= nextAttempt else { return nil }
        retryLater(now: now)
        return configuration
    }
}
