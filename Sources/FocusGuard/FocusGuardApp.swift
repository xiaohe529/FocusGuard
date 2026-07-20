import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsController: SettingsWindowController?
    private var statusBarManager: StatusBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusLogger.info("FocusGuard launching")
        // No dock icon
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.load()

        // Settings window
        let settings = SettingsWindowController()
        settings.setContentView(MainView(state: AppState.shared))
        settingsController = settings

        // Menu bar item
        let statusBar = StatusBarManager()
        statusBar.setup(state: AppState.shared, settings: settings)
        statusBarManager = statusBar
        FocusLogger.info("FocusGuard launched — status bar ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusLogger.info("FocusGuard terminating")
        AppState.shared.quitCleanup()
    }
}

@main
struct FocusGuardApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
