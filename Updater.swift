import AppKit
import CryptoKit
import os

/// Self-update from GitHub Releases — the same `MacStats.zip` that install.sh downloads.
///
/// A release build checks once a day; when a newer release exists it downloads it,
/// verifies it, swaps the bundle in place and relaunches. With "Install Updates
/// Automatically" off it still checks, but only offers the update in the menu.
///
/// Local builds (version 0.0.0, see Info.plist) never check on their own — only via
/// "Check for Updates…" — so a build installed from a checkout is not silently replaced
/// by the latest release.
final class Updater {
    struct Release {
        let version: String   // tag without the leading "v", e.g. "1.0.16"
        let zipURL: URL
        let sha256: String?   // GitHub's digest for the asset; absent on assets uploaded before mid-2025
        let pageURL: URL
    }

    enum State {
        case idle
        case checking
        case available(Release)
        case installing(Release)
    }

    /// The version local builds carry; CI stamps the release version over it.
    static let devVersion = "0.0.0"

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/openhoangnc/mac-stats/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/openhoangnc/mac-stats/releases")!
    private static let assetName = "MacStats.zip"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"
    private static let autoInstallKey = "autoInstallUpdates"
    private static let log = Logger(subsystem: "com.openhoangnc.macstats", category: "update")

    // No disk cache: nothing is left behind in ~/Library/Caches for uninstall.sh to miss.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private(set) var state: State = .idle
    /// Consulted before relaunching; return true to hold off (e.g. while the menu is open).
    var shouldDeferRelaunch: () -> Bool = { false }

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? Updater.devVersion
    private let bundleURL = Bundle.main.bundleURL
    private var timer: Timer?

    var isDevBuild: Bool { currentVersion == Self.devVersion }

    var installsAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoInstallKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoInstallKey) }
    }

    func start() {
        guard !isDevBuild else { return }
        // Hourly ticks that check only once a day has passed. Unlike a 24h timer this
        // survives sleep and relaunches, and an offline failure is retried within the hour.
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 10 * 60
        // First look shortly after launch, once login-time networking has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.tick() }
    }

    private func tick() {
        if case .available(let release) = state, installsAutomatically, diskHasRelease(release) {
            relaunchWhenIdle(into: release, userInitiated: false)
            return
        }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(last)
        if elapsed >= Self.checkInterval || elapsed < 0 {
            checkForUpdates(userInitiated: false)
        }
    }

    func checkForUpdates(userInitiated: Bool) {
        switch state {
        case .checking, .installing: return
        case .idle, .available: break
        }
        state = .checking
        fetchLatestRelease { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.state = .idle
                self.report(error, userInitiated: userInitiated)
            case .success(let release):
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                guard let release, Self.isVersion(release.version, newerThan: self.currentVersion) else {
                    self.state = .idle
                    if userInitiated { self.presentUpToDate() }
                    return
                }
                self.state = .available(release)
                if userInitiated {
                    self.promptToInstall(release)
                } else if self.installsAutomatically {
                    self.install(release, userInitiated: false)
                }
            }
        }
    }

    func installAvailableUpdate() {
        if case .available(let release) = state {
            install(release, userInitiated: true)
        }
    }

    private func install(_ release: Release, userInitiated: Bool) {
        if diskHasRelease(release) {
            relaunchWhenIdle(into: release, userInitiated: userInitiated)
            return
        }
        // The bundle changed under us (e.g. a local build installed from another account):
        // leave it alone unless asked. The menu still offers the update.
        if !userInitiated && installedVersion != currentVersion {
            return
        }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: bundleURL.path),
              fm.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) else {
            report(UpdateError.notWritable(bundleURL.path), userInitiated: userInitiated)
            return
        }
        state = .installing(release)
        Self.downloadAndInstall(release, over: bundleURL) { [weak self] error in
            guard let self else { return }
            if let error {
                self.state = .available(release)
                self.report(error, userInitiated: userInitiated)
                // Network trouble is retried on the next hourly tick rather than tomorrow;
                // a broken or incompatible release waits for the daily check.
                if Self.isTransient(error) {
                    UserDefaults.standard.removeObject(forKey: Self.lastCheckKey)
                }
            } else {
                self.relaunchWhenIdle(into: release, userInitiated: userInitiated)
            }
        }
    }

    private func relaunchWhenIdle(into release: Release, userInitiated: Bool) {
        state = .installing(release)
        if shouldDeferRelaunch() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.relaunchWhenIdle(into: release, userInitiated: userInitiated)
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        // The new instance terminates this one as it starts (main.swift); quitting here
        // too covers the case where it doesn't get that far.
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.state = .available(release)
                    self?.report(error, userInitiated: userInitiated)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: - Disk state

    /// The version on disk. It differs from `currentVersion` once something replaced the
    /// bundle while this process kept running the old code.
    private var installedVersion: String {
        let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleShortVersionString"] as? String ?? currentVersion
    }

    /// True when the bundle on disk already holds `release` or newer — another account on
    /// this Mac installed it — so restarting is all that's left to do.
    private func diskHasRelease(_ release: Release) -> Bool {
        let onDisk = installedVersion
        return onDisk != Self.devVersion && !Self.isVersion(release.version, newerThan: onDisk)
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        var x = a.split(separator: ".").map { Int($0) ?? 0 }
        var y = b.split(separator: ".").map { Int($0) ?? 0 }
        while x.count < y.count { x.append(0) }
        while y.count < x.count { y.append(0) }
        return y.lexicographicallyPrecedes(x)
    }

    // MARK: - Network & install (off the main thread)

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let digest: String?
        }
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
    }

    /// Calls back on the main thread with the latest release, or nil while its zip is
    /// still being uploaded.
    private func fetchLatestRelease(completion: @escaping (Result<Release?, Error>) -> Void) {
        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        Self.session.dataTask(with: request) { data, response, error in
            let result = Result<Release?, Error> {
                if let error { throw error }
                try Self.checkStatus(response)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let latest = try decoder.decode(GitHubRelease.self, from: data ?? Data())
                guard let asset = latest.assets.first(where: { $0.name == Self.assetName }) else { return nil }
                let version = latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName
                let sha256 = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
                return Release(version: version, zipURL: asset.browserDownloadUrl, sha256: sha256, pageURL: latest.htmlUrl)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Calls back on the main thread once the new bundle is in place, or with the reason it isn't.
    private static func downloadAndInstall(_ release: Release, over bundleURL: URL, completion: @escaping (Error?) -> Void) {
        session.downloadTask(with: URLRequest(url: release.zipURL, timeoutInterval: 60)) { location, response, error in
            // `location` is deleted when this handler returns, so claim it before hopping queues.
            let zip = Result<URL, Error> {
                if let error { throw error }
                try checkStatus(response)
                guard let location else { throw UpdateError.badResponse(nil) }
                let zip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                try FileManager.default.moveItem(at: location, to: zip)
                return zip
            }
            DispatchQueue.global(qos: .utility).async {
                var failure: Error?
                do { try install(zipAt: zip.get(), release, over: bundleURL) } catch { failure = error }
                if case .success(let url) = zip { try? FileManager.default.removeItem(at: url) }
                DispatchQueue.main.async { completion(failure) }
            }
        }.resume()
    }

    private static func install(zipAt zip: URL, _ release: Release, over bundleURL: URL) throws {
        let fm = FileManager.default
        if let expected = release.sha256 {
            let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw UpdateError.invalidDownload("checksum mismatch") }
        }

        // Unpack on the bundle's own volume so the final swap is a rename, not a copy.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        defer { try? fm.removeItem(at: work) }
        try run("/usr/bin/ditto", "-x", "-k", zip.path, work.path)

        let newApp = work.appendingPathComponent("MacStats.app")
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError.invalidDownload("it doesn't contain MacStats \(release.version)")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if let minimum = info?["LSMinimumSystemVersion"] as? String,
           isVersion(minimum, newerThan: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") {
            throw UpdateError.unsupportedSystem(minimum)
        }
        try run("/usr/bin/codesign", "--verify", "--deep", "--strict", newApp.path)

        // Swap whole bundles rather than overwriting files in place: this process keeps
        // running from the old (now unlinked) files, whereas macOS kills a process whose
        // signed executable is modified underneath it.
        _ = try fm.replaceItemAt(bundleURL, withItemAt: newApp, backupItemName: nil, options: .usingNewMetadataOnly)
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case UpdateError.badResponse = error { return true }
        return false
    }

    private static func checkStatus(_ response: URLResponse?) throws {
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200 else { throw UpdateError.badResponse(status) }
    }

    private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.invalidDownload("\(process.executableURL!.lastPathComponent) failed with status \(process.terminationStatus)")
        }
    }

    // MARK: - Alerts

    private func report(_ error: Error, userInitiated: Bool) {
        guard userInitiated else {
            Self.log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't update MacStats"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        if runModal(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "MacStats is up to date"
        alert.informativeText = isDevBuild
            ? "You're running a local build, and no release exists yet."
            : "Version \(currentVersion) is the latest release."
        runModal(alert)
    }

    private func promptToInstall(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "MacStats \(release.version) is available"
        alert.informativeText = isDevBuild
            ? "You're running a local build. Installing replaces it with the release and restarts MacStats."
            : "You have version \(currentVersion). MacStats restarts after installing."
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch runModal(alert) {
        case .alertFirstButtonReturn: install(release, userInitiated: true)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        // An accessory app's alert opens behind the frontmost app unless we activate first.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}

enum UpdateError: LocalizedError {
    case badResponse(Int?)
    case invalidDownload(String)
    case unsupportedSystem(String)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return status.map { "GitHub returned HTTP \($0)." } ?? "GitHub returned an unexpected response."
        case .invalidDownload(let reason):
            return "The downloaded update is invalid: \(reason)."
        case .unsupportedSystem(let minimum):
            return "This update requires macOS \(minimum) or later."
        case .notWritable(let path):
            return "Your account doesn't have permission to replace \(path). Download the update from GitHub, or reinstall with the install command."
        }
    }
}
