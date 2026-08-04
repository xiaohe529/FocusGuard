import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsController: SettingsWindowController?
    private var statusBarManager: StatusBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusLogger.info("FocusGuard launching")
        // No dock icon
        NSApp.setActivationPolicy(.accessory)

        installMainMenu()

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

    /// Without a main menu, Cmd+C/Cmd+V/Cmd+A don't fire in SecureField/TextField
    /// (keyboard shortcuts are dispatched via menu items with key equivalents).
    /// LSUIElement/menu-bar apps ship without one by default — install a minimal
    /// Edit menu so paste works.
    @MainActor
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        appMenuItem.submenu = {
            let appMenu = NSMenu(title: "App")
            appMenu.addItem(withTitle: "关于 FocusGuard", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            appMenu.addItem(NSMenuItem.separator())
            appMenu.addItem(withTitle: "退出 FocusGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return appMenu
        }()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editMenuItem.submenu = {
            let editMenu = NSMenu(title: "编辑")
            editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
            let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
            redoItem.keyEquivalentModifierMask = [.command, .shift]
            editMenu.addItem(redoItem)
            editMenu.addItem(NSMenuItem.separator())
            editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            return editMenu
        }()
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
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
