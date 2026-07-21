import Foundation
import AppKit
import ApplicationServices
import ServiceManagement
import CoreGraphics

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var blockingEnabled = false
    @Published var blockRules: [BlockRule] = []
    @Published var hasPassword = false
    @Published var showPasswordSheet = false
    @Published var pendingToggleAction: (() -> Void)?
    @Published var isSaving = false
    @Published var lastError: String?
    @Published var isProcessing = false
    @Published var launchAtLogin = false
    @Published var wifiDisabled = false
    @Published var focusTimerActive = false
    @Published var focusTimerEnd: Date? = nil
    @Published var emergencyUsesThisMonth = 0
    @Published var showEmergencyOverrideSheet = false
    @Published var delayedBlockActive = false
    @Published var delayedBlockEnd: Date? = nil
    @Published var delayedBlockPendingAuth = false
    @Published var delayedBlockRetryCount = 0
    @Published var delayedBlockNextRetryAt: Date? = nil
    @Published var delayedBlockLockScreen = false
    @Published var delayedBlockAllowExtension = true
    @Published var helperInstalled = false
    @Published var isInstallingHelper = false
    var helperInstallAttempted = false

    @Published var reminderEnabled = false
    @Published var reminderIntervalMinutes = 30
    @Published var showSettingsSheet = false

    private var reminderTask: Task<Void, Never>?
    private var reminderAlertInFlight = false

    /// Callback for StatusBarManager to auto-update icon on state changes
    var onBlockingStateChanged: (() -> Void)?

    let appBlocker = AppBlocker()
    let wifiBlocker = WiFiBlocker()
    let focusTimerEngine = FocusTimerEngine()

    static let monthlyEmergencyQuota = 3

    private var lastResetMonth: String = ""

    var isLocked: Bool { focusTimerActive }

    var activeTimerKind: FocusTimerState.Kind? {
        if focusTimerActive { return .focus }
        if delayedBlockActive { return .delayedBlock }
        return nil
    }

    private var settingsURL: URL {
        HostsBlocker.backupDir().appendingPathComponent("settings.json")
    }

    private var focusTimerURL: URL {
        HostsBlocker.backupDir().appendingPathComponent("focustimer.json")
    }

    func load() {
        FocusLogger.info("AppState load begin")

        if let data = try? Data(contentsOf: settingsURL),
           let saved = try? JSONDecoder().decode(SettingsStorage.self, from: data) {
            blockRules = saved.blockRules
            FocusLogger.info("Loaded \(blockRules.count) block rules from settings.json")
        } else {
            FocusLogger.info("No settings.json or decode failed — starting fresh")
        }

        hasPassword = KeychainPassword.load() != nil

        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        if let enabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool {
            blockingEnabled = enabled
        }
        delayedBlockLockScreen = UserDefaults.standard.bool(forKey: "delayedBlockLockScreen")
        delayedBlockAllowExtension = UserDefaults.standard.object(forKey: "delayedBlockAllowExtension") as? Bool ?? true

        appBlocker.updateBlockedApps(blockRules.filter { $0.type == .app && $0.enabled }.map { $0.name })
        appBlocker.setBlockingEnabled(blockingEnabled)

        appBlocker.start()
        // Check WiFi status without triggering admin prompt — deferred to avoid startup interference
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            wifiBlocker.checkStatusQuiet()
        }

        // Probe privileged helper — then restore blocking only if helper is already installed.
        // Otherwise skip restore so first open doesn't trigger an admin password prompt.
        // User clicks "开启屏蔽" to install helper and resume blocking.
        Task { @MainActor in
            self.helperInstalled = await HelperInstaller.isInstalledAndRunning()
            if !self.helperInstalled {
                FocusLogger.info("Helper not installed — skipping blocking restore on launch")
                if self.blockingEnabled {
                    self.blockingEnabled = false
                    self.appBlocker.setBlockingEnabled(false)
                }
                return
            }
            guard self.blockingEnabled else { return }
            let domains = self.blockRules.filter { $0.type == .website && $0.enabled }.map { $0.name }
            if !domains.isEmpty {
                FocusLogger.info("Restoring website blocking for \(domains.count) domains")
                Task {
                    do {
                        try await HostsBlocker.apply(domains: domains)
                        self.lastError = nil
                    } catch {
                        FocusLogger.error("Restore blocking failed: \(error.localizedDescription)")
                        self.lastError = "恢复屏蔽失败：\(error.localizedDescription)"
                        self.blockingEnabled = false
                        self.appBlocker.setBlockingEnabled(false)
                    }
                }
            }
        }

        loadFocusTimer()

        reminderEnabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
        let storedInterval = UserDefaults.standard.object(forKey: "reminderIntervalMinutes") as? Int
        reminderIntervalMinutes = storedInterval ?? 30
        if reminderIntervalMinutes < 1 { reminderIntervalMinutes = 1 }
        startReminderLoop()

        FocusLogger.info("AppState load complete — blockingEnabled=\(blockingEnabled) hasPassword=\(hasPassword)")
    }

    private func loadFocusTimer() {
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in
                self?.focusTimerExpired()
            }
        }

        let currentMonth = Self.currentMonthString()
        var loaded = FocusTimerState(endTimestamp: nil,
                                     emergencyUsesThisMonth: 0,
                                     lastResetMonth: currentMonth)

        if let data = try? Data(contentsOf: focusTimerURL),
           let saved = try? JSONDecoder().decode(FocusTimerState.self, from: data) {
            loaded = saved
        }

        // Monthly reset
        if loaded.lastResetMonth != currentMonth {
            FocusLogger.info("Month changed \(loaded.lastResetMonth) → \(currentMonth), resetting emergency quota")
            loaded.emergencyUsesThisMonth = 0
            loaded.lastResetMonth = currentMonth
        }
        emergencyUsesThisMonth = loaded.emergencyUsesThisMonth
        lastResetMonth = loaded.lastResetMonth

        // Reset transient timer state — will be repopulated below
        focusTimerActive = false
        focusTimerEnd = nil
        delayedBlockActive = false
        delayedBlockEnd = nil
        delayedBlockPendingAuth = false
        delayedBlockRetryCount = 0
        delayedBlockNextRetryAt = nil

        // Resume active timer if end is still in the future
        if let end = loaded.endTimestamp, end > Date() {
            let kind = loaded.kind ?? .focus
            switch kind {
            case .focus:
                focusTimerEnd = end
                focusTimerActive = true
                focusTimerEngine.onExpire = { [weak self] in
                    Task { @MainActor in self?.focusTimerExpired() }
                }
                FocusLogger.info("Resumed active focus timer, ends at \(end)")
            case .delayedBlock:
                delayedBlockEnd = end
                delayedBlockActive = true
                focusTimerEngine.onExpire = { [weak self] in
                    Task { @MainActor in self?.delayedBlockExpired() }
                }
                FocusLogger.info("Resumed active delayed-block timer, ends at \(end)")
            }
            focusTimerEngine.start(endTimestamp: end)
        } else if loaded.delayedBlockPendingAuth == true {
            // Timer expired but blocking failed (user cancelled admin prompt) — restore pending state
            delayedBlockPendingAuth = true
            delayedBlockRetryCount = loaded.delayedBlockRetryCount ?? 0
            FocusLogger.info("Resumed pending-auth state, retryCount=\(delayedBlockRetryCount)")
            // Pop the alert immediately on restart — global nag
            presentExtendAlert()
        } else {
            saveFocusTimer()
        }
    }

    private static func currentMonthString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    func startFocusTimer(minutes: Int) {
        guard !delayedBlockActive else {
            lastError = "延时屏蔽进行中，无法启动专注计时"
            return
        }
        guard blockingEnabled else {
            lastError = "请先开启屏蔽再启动专注计时"
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        focusTimerEnd = end
        focusTimerActive = true
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.focusTimerExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        FocusLogger.info("Started focus timer: \(minutes) min, ends at \(end)")
    }

    func focusTimerExpired() {
        FocusLogger.info("Focus timer expired naturally")
        focusTimerActive = false
        focusTimerEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()
    }

    /// Returns true on success (timer cleared). Returns false on wrong password
    /// or quota exhausted, setting lastError.
    func emergencyOverride(password: String) -> Bool {
        guard KeychainPassword.verify(password) else {
            FocusLogger.error("Emergency override failed: wrong password")
            lastError = "密码错误"
            return false
        }
        guard emergencyUsesThisMonth < Self.monthlyEmergencyQuota else {
            FocusLogger.error("Emergency override failed: quota exhausted (\(emergencyUsesThisMonth)/\(Self.monthlyEmergencyQuota))")
            lastError = "本月紧急退出次数已用完"
            return false
        }
        emergencyUsesThisMonth += 1
        focusTimerActive = false
        focusTimerEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        FocusLogger.info("Emergency override succeeded, uses this month: \(emergencyUsesThisMonth)")
        return true
    }

    private func saveFocusTimer() {
        let storage = FocusTimerState(kind: activeTimerKind,
                                      endTimestamp: activeTimerKind != nil ? (focusTimerActive ? focusTimerEnd : delayedBlockEnd) : nil,
                                      emergencyUsesThisMonth: emergencyUsesThisMonth,
                                      lastResetMonth: lastResetMonth,
                                      delayedBlockPendingAuth: delayedBlockPendingAuth,
                                      delayedBlockRetryCount: delayedBlockRetryCount)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: focusTimerURL)
        } catch {
            FocusLogger.error("saveFocusTimer failed: \(error.localizedDescription)")
            lastError = "保存计时状态失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Delayed block timer

    func startDelayedBlock(minutes: Int) {
        guard !blockingEnabled else {
            lastError = "屏蔽已开启，无需延时屏蔽"
            return
        }
        guard !focusTimerActive else {
            lastError = "专注计时进行中，无法启动延时屏蔽"
            return
        }
        guard !delayedBlockActive else { return }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        delayedBlockEnd = end
        delayedBlockActive = true
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.delayedBlockExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        FocusLogger.info("Started delayed-block timer: \(minutes) min, ends at \(end)")
    }

    func delayedBlockExpired() {
        FocusLogger.info("Delayed-block timer expired naturally")
        delayedBlockActive = false
        delayedBlockEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()

        if delayedBlockAllowExtension {
            // Show choice dialog: block now or extend
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "clock.badge.exclamationmark", accessibilityDescription: nil)
            alert.messageText = "延时屏蔽时间到"
            var info = "倒计时已结束。"
            if delayedBlockRetryCount < 1 {
                info += "（可延长 1 次）"
            } else {
                info += "（延长次数已用完）"
            }
            alert.informativeText = info
            alert.addButton(withTitle: "立即屏蔽")
            if delayedBlockRetryCount < 1 {
                alert.addButton(withTitle: "再等 5 分钟")
                alert.addButton(withTitle: "再等 10 分钟")
            }
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            let idx = Int(response.rawValue) - 1000

            switch idx {
            case 0:
                Task { await attemptDelayedBlockEnable(initialAlert: true) }
            case 1 where delayedBlockRetryCount < 1:
                extendDelayedBlock(minutes: 5)
            case 2 where delayedBlockRetryCount < 1:
                extendDelayedBlock(minutes: 10)
            default:
                break
            }
        } else {
            // No extension: directly block
            Task { await attemptDelayedBlockEnable(initialAlert: true) }
        }
    }

    func blockNow() {
        guard delayedBlockActive else { return }
        FocusLogger.info("blockNow — skipping delayed-block countdown, attempting to enable blocking")
        delayedBlockActive = false
        delayedBlockEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()
        Task { await attemptDelayedBlockEnable(initialAlert: true) }
    }

    private func lockScreen() {
        // CGEvent posting requires Accessibility permission. Without it, the
        // shortcut is silently dropped — surface the failure to the user.
        guard AXIsProcessTrusted() else {
            FocusLogger.error("lockScreen: Accessibility permission missing — Control+Command+Q will not fire")
            lastError = "锁屏失败：请在「系统设置 → 隐私与安全性 → 辅助功能」中授权 FocusGuard"
            return
        }
        // Simulate Control+Command+Q (macOS lock screen shortcut)
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: true)
        keyDown?.flags = [.maskControl, .maskCommand]
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x0C, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)

        FocusLogger.info("lockScreen: screen locked via keyboard shortcut")
    }

    func cancelDelayedBlock() {
        guard delayedBlockActive else { return }
        FocusLogger.info("cancelDelayedBlock — clearing delayed-block timer without enabling blocking")
        delayedBlockActive = false
        delayedBlockEnd = nil
        focusTimerEngine.stop()
        saveFocusTimer()
    }

    /// Called when delayed-block timer expires (or via "立即授权" retry button).
    /// Tries to enable blocking; on success clears all pending state.
    /// On failure (user cancelled admin prompt) sets pendingAuth and pops
    /// the global NSAlert (immediate on first expiry, 30s-scheduled on retry failure).
    func attemptDelayedBlockEnable(initialAlert: Bool = false) async {
        await enableBlocking()
        if blockingEnabled {
            FocusLogger.info("Delayed-block enable succeeded — clearing pending state")
            delayedBlockPendingAuth = false
            delayedBlockRetryCount = 0
            delayedBlockNextRetryAt = nil
            stopPendingAlertLoop()
            saveFocusTimer()
            if delayedBlockLockScreen {
                lockScreen()
            }
            return
        }
        // Failed — user cancelled admin prompt
        FocusLogger.info("Delayed-block enable failed (user cancelled) — retryCount=\(delayedBlockRetryCount)")
        delayedBlockPendingAuth = true
        saveFocusTimer()
        stopPendingAlertLoop()
        if initialAlert {
            presentExtendAlert()
        } else {
            scheduleNextPendingAlert()
        }
    }

    /// Extend the timer after expiry (user picked 5 or 10 min). Consumes one of 2 allowed extensions.
    func extendDelayedBlock(minutes: Int) {
        guard delayedBlockPendingAuth else { return }
        guard delayedBlockRetryCount < 1 else { return }
        delayedBlockRetryCount += 1
        delayedBlockPendingAuth = false
        stopPendingAlertLoop()
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        delayedBlockEnd = end
        delayedBlockActive = true
        focusTimerEngine.onExpire = { [weak self] in
            Task { @MainActor in self?.delayedBlockExpired() }
        }
        focusTimerEngine.start(endTimestamp: end)
        saveFocusTimer()
        FocusLogger.info("Extended delayed-block by \(minutes) min (used \(delayedBlockRetryCount)/2), new end=\(end)")
    }

    /// User-initiated retry from pending state — re-runs the admin prompt.
    func retryDelayedBlockNow() {
        guard delayedBlockPendingAuth else { return }
        FocusLogger.info("retryDelayedBlockNow — user-initiated retry")
        Task { await attemptDelayedBlockEnable(initialAlert: false) }
    }

    // MARK: - Pending-alert loop (global NSAlert that re-pops every 30s)

    private var pendingAlertTask: Task<Void, Never>?
    private var pendingAlertInFlight = false

    /// Pop the global NSAlert immediately. Modal — blocks main thread until user responds.
    /// After dismissal, if still pending, schedules a 30s re-pop.
    func presentExtendAlert() {
        guard delayedBlockPendingAuth else { return }
        guard !pendingAlertInFlight else { return }
        pendingAlertInFlight = true
        stopPendingAlertLoop()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        alert.messageText = "屏蔽未生效"
        var subtitle = "到点了但未授权修改 hosts，请选择："
        if delayedBlockRetryCount < 1 {
            subtitle += "（已延长 \(delayedBlockRetryCount) / 1 次）"
        } else {
            subtitle += "（延长次数已用完）"
        }
        alert.informativeText = subtitle

        if delayedBlockRetryCount < 1 {
            alert.addButton(withTitle: "再等 5 分钟")
            alert.addButton(withTitle: "再等 10 分钟")
            alert.addButton(withTitle: "立即授权")
            alert.addButton(withTitle: "取消")
        } else {
            alert.addButton(withTitle: "立即授权")
            alert.addButton(withTitle: "取消")
        }

        let response = alert.runModal()
        pendingAlertInFlight = false

        // NSModalResponseFirstButtonReturned = 1000; index 0-based
        let idx = Int(response.rawValue) - 1000

        if delayedBlockRetryCount < 1 {
            switch idx {
            case 0: extendDelayedBlock(minutes: 5)
            case 1: extendDelayedBlock(minutes: 10)
            case 2: retryDelayedBlockNow()
            default: break  // 取消 — leave pending
            }
        } else {
            switch idx {
            case 0: retryDelayedBlockNow()
            default: break
            }
        }

        // If still pending after handling, schedule 30s re-pop
        if delayedBlockPendingAuth {
            scheduleNextPendingAlert()
        }
    }

    /// Schedule a 30s-delayed re-pop of the alert. Cancels any previously scheduled pop.
    func scheduleNextPendingAlert() {
        pendingAlertTask?.cancel()
        guard delayedBlockPendingAuth else { return }
        delayedBlockNextRetryAt = Date().addingTimeInterval(30)
        pendingAlertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { return }
            guard self.delayedBlockPendingAuth else { return }
            self.presentExtendAlert()
        }
    }

    private func stopPendingAlertLoop() {
        pendingAlertTask?.cancel()
        pendingAlertTask = nil
        delayedBlockNextRetryAt = nil
    }

    func save() async -> Bool {
        let storage = SettingsStorage(blockRules: blockRules)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: settingsURL)
        } catch {
            FocusLogger.error("save settings failed: \(error.localizedDescription)")
            lastError = "保存设置失败：\(error.localizedDescription)"
            return false
        }
        UserDefaults.standard.set(blockingEnabled, forKey: "blockingEnabled")
        UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")

        appBlocker.updateBlockedApps(blockRules.filter { $0.type == .app && $0.enabled }.map { $0.name })
        appBlocker.setBlockingEnabled(blockingEnabled)

        if blockingEnabled && helperInstalled {
            let domains = blockRules.filter { $0.type == .website && $0.enabled }.map { $0.name }
            do {
                if domains.isEmpty {
                    try await HostsBlocker.clear()
                } else {
                    try await HostsBlocker.apply(domains: domains)
                }
                lastError = nil
            } catch {
                FocusLogger.error("HostsBlocker apply failed: \(error.localizedDescription)")
                lastError = "更新屏蔽规则失败：\(error.localizedDescription)"
                return false
            }
        }
        return true
    }

    func setPassword(_ password: String) {
        guard !isLocked else {
            lastError = "专注计时中，无法修改密码"
            return
        }
        do {
            try KeychainPassword.save(password)
            hasPassword = !password.isEmpty
            FocusLogger.info("Password set/changed")
        } catch {
            FocusLogger.error("KeychainPassword.save failed: \(error.localizedDescription)")
            lastError = "密码保存失败：\(error.localizedDescription)"
        }
    }

    /// Verify password before changing to new one
    func changePassword(oldPassword: String, newPassword: String) {
        guard !isLocked else {
            lastError = "专注计时中，无法修改密码"
            return
        }
        guard KeychainPassword.verify(oldPassword) else { return }
        setPassword(newPassword)
    }

    func enableBlocking() async {
        // Install helper if not already installed (one-time admin prompt)
        if !helperInstalled && !helperInstallAttempted {
            helperInstallAttempted = true

            // Show explanation before the admin prompt
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            alert.messageText = "需要一次性授权"
            alert.informativeText = "FocusGuard 需要安装后台助手来静默更新屏蔽规则，避免每次操作都弹出密码框。\n\n这只需授权一次，之后所有屏蔽操作都会在后台静默执行。\n\n点击「好」后将弹出系统密码输入框。"
            alert.addButton(withTitle: "好")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                isInstallingHelper = true
                let ok = await HelperInstaller.install()
                if ok {
                    for i in 0..<3 {
                        try? await Task.sleep(for: .seconds(1))
                        helperInstalled = await HelperConnection.shared.forceProbe()
                        if helperInstalled { break }
                        FocusLogger.info("Helper probe retry \(i+1)/3 failed")
                    }
                    if !helperInstalled {
                        FocusLogger.info("Helper installed but probe failed after retries — will retry later")
                        helperInstallAttempted = false
                    }
                } else {
                    FocusLogger.info("Helper install failed — falling back to per-op osascript")
                    helperInstallAttempted = false
                }
                isInstallingHelper = false
            } else {
                FocusLogger.info("User cancelled helper install")
                helperInstallAttempted = false
            }
        }

        FocusLogger.info("enableBlocking — websites=\(blockRules.filter { $0.type == .website && $0.enabled }.count), apps=\(blockRules.filter { $0.type == .app && $0.enabled }.count)")
        isProcessing = true
        onBlockingStateChanged?()
        let domains = blockRules.filter { $0.type == .website && $0.enabled }.map { $0.name }
        if !domains.isEmpty {
            do {
                try await HostsBlocker.apply(domains: domains)
                blockingEnabled = true
                appBlocker.setBlockingEnabled(true)
                lastError = nil
            } catch {
                FocusLogger.error("enableBlocking failed: \(error.localizedDescription)")
                lastError = "屏蔽失败：\(error.localizedDescription)"
                isProcessing = false
                onBlockingStateChanged?()
                return
            }
        } else {
            blockingEnabled = true
            appBlocker.setBlockingEnabled(true)
        }
        isProcessing = false
        onBlockingStateChanged?()
        restartReminderIfNeeded()
        _ = await save()
    }

    func disableBlocking() async {
        FocusLogger.info("disableBlocking")
        isProcessing = true
        onBlockingStateChanged?()
        do {
            try await HostsBlocker.clear()
            blockingEnabled = false
            appBlocker.setBlockingEnabled(false)
            lastError = nil
        } catch {
            FocusLogger.error("disableBlocking failed: \(error.localizedDescription)")
            lastError = "停止失败：\(error.localizedDescription)"
            isProcessing = false
            onBlockingStateChanged?()
            return
        }
        isProcessing = false
        onBlockingStateChanged?()
        restartReminderIfNeeded()
        _ = await save()
    }

    func toggleBlocking() {
        guard !isLocked else {
            lastError = "专注计时中，无法修改屏蔽状态"
            return
        }
        if blockingEnabled {
            if !hasPassword {
                Task { await disableBlocking() }
            } else {
                pendingToggleAction = { [weak self] in Task { await self?.disableBlocking() } }
                showPasswordSheet = true
            }
        } else if !hasPassword {
            // Proactively remind user to set a password before enabling blocking
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
            alert.messageText = "建议设置屏蔽密码"
            alert.informativeText = "你还没有设置密码。没有密码的话，任何人点击「停止屏蔽」都可以直接关闭，之前忍住的冲动可能一秒破功。\n\n建议现在设置，给关闭屏蔽增加一点操作摩擦。"
            alert.addButton(withTitle: "设置密码")
            alert.addButton(withTitle: "稍后再说")
            if alert.runModal() == .alertFirstButtonReturn {
                showSettingsSheet = true
                return
            }
            Task { await enableBlocking() }
        } else {
            Task { await enableBlocking() }
        }
    }

    func installHelper() async {
        guard !helperInstalled else { return }
        helperInstallAttempted = true
        isInstallingHelper = true
        let ok = await HelperInstaller.install()
        if ok {
            for i in 0..<3 {
                try? await Task.sleep(for: .seconds(1))
                helperInstalled = await HelperConnection.shared.forceProbe()
                if helperInstalled { break }
                FocusLogger.info("Helper probe retry \(i+1)/3 failed")
            }
            if !helperInstalled {
                FocusLogger.info("Helper installed but probe failed after retries")
                helperInstallAttempted = false
            }
        } else {
            FocusLogger.info("Helper install failed")
            helperInstallAttempted = false
            lastError = "助手安装失败，请稍后重试"
        }
        isInstallingHelper = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            FocusLogger.info("Launch at login set to \(enabled)")
        } catch {
            FocusLogger.error("setLaunchAtLogin failed: \(error.localizedDescription)")
            lastError = "设置开机启动失败：\(error.localizedDescription)"
        }
        Task { _ = await save() }
    }

    func quitCleanup() {
        FocusLogger.info("quitCleanup")
        appBlocker.stop()
        focusTimerEngine.stop()
        stopPendingAlertLoop()
        stopReminderLoop()
        // Don't clear hosts — let blocking persist across quit
        // Don't reset focusTimerActive/delayedBlock* — timer survives by endTimestamp
    }

    // MARK: - Reminder

    func setReminderEnabled(_ enabled: Bool) {
        reminderEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "reminderEnabled")
        if enabled {
            startReminderLoop()
        } else {
            stopReminderLoop()
        }
    }

    func setReminderInterval(minutes: Int) {
        var v = minutes
        if v < 1 { v = 1 }
        reminderIntervalMinutes = v
        UserDefaults.standard.set(v, forKey: "reminderIntervalMinutes")
        restartReminderIfNeeded()
    }

    private func startReminderLoop() {
        stopReminderLoop()
        guard reminderEnabled else { return }
        reminderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Skip if any blocking state active
                guard self.reminderEnabled,
                      !self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive,
                      !self.delayedBlockPendingAuth else {
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                let interval = self.reminderIntervalMinutes * 60
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                guard self.reminderEnabled,
                      !self.blockingEnabled,
                      !self.focusTimerActive,
                      !self.delayedBlockActive else { continue }
                self.presentReminderAlert()
            }
        }
    }

    private func stopReminderLoop() {
        reminderTask?.cancel()
        reminderTask = nil
    }

    private func restartReminderIfNeeded() {
        // Restart to pick up new state (interval change or blocking state change)
        if reminderEnabled { startReminderLoop() }
    }

    private func presentReminderAlert() {
        guard !reminderAlertInFlight else { return }
        reminderAlertInFlight = true
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: nil)
        alert.messageText = "未屏蔽提醒"
        alert.informativeText = "您已经 \(reminderIntervalMinutes) 分钟没有开启屏蔽了，现在开启吗？"
        alert.addButton(withTitle: "立即开启")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "不再提醒")
        let response = alert.runModal()
        reminderAlertInFlight = false
        switch Int(response.rawValue) - 1000 {
        case 0:
            Task { await enableBlocking() }
        case 2:
            setReminderEnabled(false)
        default:
            break
        }
    }
}

struct SettingsStorage: Codable {
    let blockRules: [BlockRule]
}
