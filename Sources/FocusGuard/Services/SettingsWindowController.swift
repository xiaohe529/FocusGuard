import AppKit
import SwiftUI

/// Settings window controller — .regular policy with LSUIElement hides dock icon while keeping proper window activation.
class SettingsWindowController: NSWindowController {

    private var hostedView: Any?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "FocusGuard"
        window.minSize = NSSize(width: 500, height: 500)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FocusGuardSettings")

        super.init(window: window)

        window.delegate = self
    }

    func setContentView<V: View>(_ view: V) {
        let vc = NSHostingController(rootView: view.frame(minWidth: 500, minHeight: 500))
        contentViewController = vc
        hostedView = vc
        window?.minSize = NSSize(width: 500, height: 500)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        hide()
    }
}
