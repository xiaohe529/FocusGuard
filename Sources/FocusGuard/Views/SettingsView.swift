import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showPasswordSheet = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String = ""
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false
    @State private var recoveryInput1 = ""
    @State private var recoveryInput2 = ""
    @State private var revealedPassword: String?
    @State private var recoveryError: String = ""

    @State private var deletePwdInput1 = ""
    @State private var deletePwdInput2 = ""
    @State private var deletePwdError: String = ""
    @State private var deletePwdSuccess = false

    @FocusState private var passwordFieldFocus: PasswordField?

    enum PasswordField: Hashable { case old, new, confirm }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    Divider().padding(.horizontal, -16)
                    delayedBlockSection
                    Divider().padding(.horizontal, -16)
                    reminderSection
                    Divider().padding(.horizontal, -16)
                    passwordSection
                    Divider().padding(.horizontal, -16)
                    advancedSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 660)
        .sheet(isPresented: $showPasswordSheet, onDismiss: resetPasswordFields) {
            passwordSheet
        }
        .alert("确认卸载助手", isPresented: $showUninstallConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                Task { await performUninstall() }
            }
        } message: {
            Text("将卸载后台助手。下次开启屏蔽时需要重新授权安装。屏蔽规则与密码不会被清除。")
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack {
            Text("设置").font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - 通用

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("通用")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $state.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机启动")
                            .font(.subheadline)
                        Text("登录时自动启动 FocusGuard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: state.launchAtLogin) { _, v in state.setLaunchAtLogin(v) }

                HStack {
                    Image(systemName: state.helperInstalled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(state.helperInstalled ? .green : .orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("后台助手")
                            .font(.subheadline)
                        Text(state.helperInstalled
                             ? "已安装，屏蔽操作静默执行"
                             : "未安装，首次操作将请求授权")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.helperInstalled {
                        Button("卸载") { showUninstallConfirm = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isUninstalling)
                    } else {
                        Button {
                            Task { await state.installHelper() }
                        } label: {
                            Text(state.isInstallingHelper ? "安装中…" : "安装")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isUninstalling || state.isInstallingHelper)
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 延时屏蔽

    private var delayedBlockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("延时屏蔽")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.delayedBlockLockScreen },
                    set: { newValue in
                        if newValue && !AXIsProcessTrusted() {
                            let opts: NSDictionary = ["AXTrustedCheckOptionPrompt" as String: true]
                            _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
                            state.lastError = "已弹出系统授权框，请到「系统设置 → 隐私与安全性 → 辅助功能」中授权 FocusGuard。授权前锁屏不会生效。"
                        }
                        state.delayedBlockLockScreen = newValue
                        UserDefaults.standard.set(newValue, forKey: "delayedBlockLockScreen")
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("到期后锁屏")
                            .font(.subheadline)
                        Text("延时屏蔽结束后自动锁定屏幕")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: Binding(
                    get: { state.delayedBlockAllowExtension },
                    set: {
                        state.delayedBlockAllowExtension = $0
                        UserDefaults.standard.set($0, forKey: "delayedBlockAllowExtension")
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许延长")
                            .font(.subheadline)
                        Text("到期时提供「再等 5/10 分钟」选项，最多 1 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 定时提醒

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("定时提醒")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { state.reminderEnabled },
                    set: { state.setReminderEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未屏蔽时定时提醒")
                            .font(.subheadline)
                        Text("未开启屏蔽时，每隔指定时间弹窗提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if state.reminderEnabled {
                    HStack {
                        Text("提醒间隔")
                            .font(.subheadline)
                        Spacer()
                        Stepper(value: Binding(
                            get: { state.reminderIntervalMinutes },
                            set: { state.setReminderInterval(minutes: $0) }
                        ), in: 1...240, step: 5) {
                            Text("\(state.reminderIntervalMinutes) 分钟")
                                .font(.subheadline)
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                    }
                    Text("屏蔽中、专注计时中、延时屏蔽中均不弹提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 密码

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("密码")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("屏蔽密码")
                            .font(.subheadline)
                        Text(state.hasPassword ? "已设置" : "未设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(state.hasPassword ? "修改" : "设置") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("设置密码后，每次停止屏蔽都需要验证。目的是增加操作摩擦，让你在冲动想刷网站时多一道门槛——多犹豫 3 秒，可能就忍住了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 高级

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("高级")
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("为防止误操作，请输入恢复码 `123456789` 两次以查看当前屏蔽密码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecureField("恢复码", text: $recoveryInput1)
                            .textFieldStyle(.roundedBorder)
                        SecureField("再次输入恢复码", text: $recoveryInput2)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { recoverPassword() }
                        Button {
                            recoverPassword()
                        } label: {
                            Label("显示密码", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryInput1.isEmpty || recoveryInput1 != recoveryInput2)
                        if !recoveryError.isEmpty {
                            Text(recoveryError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let pwd = revealedPassword {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("当前屏蔽密码")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(pwd)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("忘记密码？")
                        .font(.subheadline)
                }

                Divider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("删除密码后，停止屏蔽将不再需要验证。请输入恢复码 `123456789` 两次以确认删除。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecureField("恢复码", text: $deletePwdInput1)
                            .textFieldStyle(.roundedBorder)
                        SecureField("再次输入恢复码", text: $deletePwdInput2)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { deletePassword() }
                        Button {
                            deletePassword()
                        } label: {
                            Label("删除密码", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(deletePwdInput1.isEmpty || deletePwdInput1 != deletePwdInput2)
                        if !deletePwdError.isEmpty {
                            Text(deletePwdError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if deletePwdSuccess {
                            Text("密码已删除")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("删除密码")
                        .font(.subheadline)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 密码修改 sheet

    private var passwordSheet: some View {
        VStack(spacing: 16) {
            Text(state.hasPassword ? "修改屏蔽密码" : "设置屏蔽密码")
                .font(.headline)
            if state.hasPassword {
                SecureField("输入旧密码", text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($passwordFieldFocus, equals: .old)
                    .onSubmit { passwordFieldFocus = .new }
            }
            SecureField(state.hasPassword ? "输入新密码" : "输入密码", text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($passwordFieldFocus, equals: .new)
                .onSubmit { passwordFieldFocus = .confirm }
            SecureField("确认密码", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($passwordFieldFocus, equals: .confirm)
                .onSubmit { savePassword() }
            if !passwordError.isEmpty {
                Text(passwordError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            HStack(spacing: 16) {
                Button("取消") {
                    showPasswordSheet = false
                }
                Button(state.hasPassword ? "保存" : "设置") {
                    savePassword()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPassword != confirmPassword || newPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 320, height: state.hasPassword ? 320 : 240)
        .onAppear {
            DispatchQueue.main.async {
                passwordFieldFocus = state.hasPassword ? .old : .new
            }
        }
    }

    private func resetPasswordFields() {
        oldPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordError = ""
    }

    private func savePassword() {
        guard newPassword == confirmPassword else {
            passwordError = "两次输入不一致"
            return
        }
        guard !newPassword.isEmpty else {
            passwordError = "密码不能为空"
            return
        }
        if state.hasPassword {
            guard !oldPassword.isEmpty else {
                passwordError = "请输入旧密码"
                return
            }
            guard KeychainPassword.verify(oldPassword) else {
                passwordError = "旧密码错误"
                return
            }
        }
        state.setPassword(newPassword)
        showPasswordSheet = false
    }

    // MARK: - 找回密码 / 删除密码 / 卸载

    private func recoverPassword() {
        guard recoveryInput1 == "123456789", recoveryInput1 == recoveryInput2 else {
            recoveryError = "恢复码不正确，需输入 123456789 且两次一致"
            revealedPassword = nil
            return
        }
        recoveryError = ""
        if let pwd = KeychainPassword.load(), !pwd.isEmpty {
            revealedPassword = pwd
        } else {
            revealedPassword = nil
            recoveryError = "尚未设置屏蔽密码"
        }
    }

    private func deletePassword() {
        guard deletePwdInput1 == "123456789", deletePwdInput1 == deletePwdInput2 else {
            deletePwdError = "恢复码不正确，需输入 123456789 且两次一致"
            deletePwdSuccess = false
            return
        }
        guard KeychainPassword.load() != nil else {
            deletePwdError = "尚未设置屏蔽密码"
            deletePwdSuccess = false
            return
        }
        deletePwdError = ""
        KeychainPassword.delete()
        state.hasPassword = false
        deletePwdSuccess = true
        deletePwdInput1 = ""
        deletePwdInput2 = ""
        FocusLogger.info("Password deleted via settings")
    }

    private func performUninstall() async {
        isUninstalling = true
        let ok = await HelperInstaller.uninstall()
        if ok {
            state.helperInstalled = false
            state.helperInstallAttempted = false
        } else {
            recoveryError = "卸载失败，请稍后重试"
        }
        isUninstalling = false
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }
}