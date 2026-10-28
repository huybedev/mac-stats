import AppKit
import SwiftUI

// The protocol lets the existing macOS 11 app own a macOS 14 feature.
protocol FanFeature: AnyObject {
    var shouldDeferUpdate: Bool { get }
    func showWindow()
    func prepareToQuit(completion: @escaping () -> Void)
}

@available(macOS 14.0, *)
final class FanFeatureController: FanFeature {
    private var model: FanAppModel?
    private var window: NSWindow?

    init() {
        if UserDefaults.standard.bool(forKey: "fanControl.startCurve") { model = FanAppModel() }
    }

    var shouldDeferUpdate: Bool { model?.busy == true || window?.isVisible == true }

    func showWindow() {
        if window == nil {
            let model = self.model ?? FanAppModel()
            self.model = model
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1030, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "MacStats — Fan Control"
            window.contentView = NSHostingView(rootView: FanDashboard(model: model)
                .frame(minWidth: 920, minHeight: 740)
                .preferredColorScheme(.dark))
            window.contentMinSize = NSSize(width: 920, height: 740)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("MacStatsFanControl")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareToQuit(completion: @escaping () -> Void) {
        guard let model else { completion(); return }
        model.prepareToQuit(completion: completion)
    }
}
