import SwiftUI

enum UnlockField: Hashable {
    case password
}

struct MainView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var emergencyPasswordInput = ""
    @State private var emergencyPasswordError = false
    @FocusState private var unlockFocus: UnlockField?
    @FocusState private var emergencyFocus: Bool

    let tabLabels = ["网站屏蔽", "App屏蔽", "专注计时", "网络控制"]
    let tabIcons = ["globe", "xmark.app", "timer", "network.slash"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — soft segmented style
            HStack(spacing: 2) {
                ForEach(0..<tabLabels.count, id: \.self) { i in
                    Button {
                        selectedTab = i
                    } label: {
                        Label(tabLabels[i], systemImage: tabIcons[i])
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(selectedTab == i ? .primary : .secondary)
                            .background(
                                selectedTab == i ? Color.secondary.opacity(0.15) : Color.clear,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Status banners (low-key, for focus-timer / delayed-block states)
            if state.focusTimerActive {
                statusBanner(
                    icon: "lock.fill",
                    color: .focusActive,
                    actionTitle: "紧急退出",
                    actionColor: .focusDanger,
                    actionDisabled: state.emergencyUsesThisMonth >= AppState.monthlyEmergencyQuota,
                    action: { state.showEmergencyOverrideSheet = true }
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("专注计时中 · 剩余 \(remainingString(end: state.focusTimerEnd))")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
            } else if state.delayedBlockActive {
                statusBanner(
                    icon: "clock.badge.exclamationmark",
                    color: .focusAccent,
                    actionTitle: nil,
                    actionColor: nil,
                    actionDisabled: false,
                    action: {}
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("延时屏蔽倒计时 · 剩余 \(remainingString(end: state.delayedBlockEnd)) · 到点自动屏蔽")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
            } else if state.delayedBlockPendingAuth {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: .focusDanger,
                    actionTitle: "去授权",
                    actionColor: .focusDanger,
                    actionDisabled: false,
                    action: { selectedTab = 2 }
                ) {
                    Text("屏蔽未生效 · 到点未授权")
                        .font(.subheadline)
                }
            }

            // Password not set reminder (low-key)
            if state.blockingEnabled && !state.hasPassword {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundStyle(Color.focusDanger)
                    Text("未设置屏蔽密码，停止屏蔽无需验证。建议设置，为冲动解除增加一道门槛。")
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                    Spacer()
                    Button("设置") { state.showSettingsSheet = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Error banner (low-key)
            if let error = state.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.focusDanger)
                    Text(error).font(.caption).foregroundStyle(Color.focusDanger)
                    Spacer()
                    Button("清除") { state.lastError = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.focusDanger)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.focusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Scrollable content
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: WebsiteListView(state: state)
                    case 1: AppListView(state: state)
                    case 2: FocusTimerView(state: state)
                    default: WiFiView(state: state)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Bottom control bar (full-width bar, bottom margin only)
            controlBar
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 500, minHeight: 500, alignment: .top)
        .sheet(isPresented: $state.showPasswordSheet, onDismiss: {
                passwordInput = ""
                passwordError = false
                state.pendingToggleAction = nil
                state.pendingActionLabel = ""
                state.lastError = nil
            }) {
                VStack(spacing: 16) {
                    Text("输入密码\(state.pendingActionLabel)")
                        .font(.headline)
                    SecureField("输入密码", text: $passwordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($unlockFocus, equals: .password)
                        .onSubmit { verifyPassword() }
                    if passwordError {
                        Text("密码错误").foregroundStyle(.red).font(.caption)
                    }
                    HStack(spacing: 16) {
                        Button("取消") {
                            state.showPasswordSheet = false
                            passwordInput = ""
                            passwordError = false
                            state.pendingToggleAction = nil
                            state.pendingActionLabel = ""
                            state.lastError = nil
                        }
                        Button("确认") { verifyPassword() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 300, height: 180)
                .onAppear {
                    DispatchQueue.main.async {
                        unlockFocus = .password
                    }
                }
            }
        .sheet(isPresented: $state.showSettingsSheet) {
            SettingsView(state: state)
        }
        .sheet(isPresented: $state.showEmergencyOverrideSheet, onDismiss: {
                emergencyPasswordInput = ""
                emergencyPasswordError = false
            }) {
                VStack(spacing: 16) {
                    Text("紧急退出专注计时")
                        .font(.headline)
                    Text("本月已用 \(state.emergencyUsesThisMonth) / \(AppState.monthlyEmergencyQuota) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入密码", text: $emergencyPasswordInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($emergencyFocus)
                        .onSubmit { confirmEmergencyOverride() }
                    if emergencyPasswordError {
                        Text(state.lastError ?? "密码错误")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    HStack(spacing: 16) {
                        Button("取消") {
                            state.showEmergencyOverrideSheet = false
                            emergencyPasswordInput = ""
                            emergencyPasswordError = false
                        }
                        Button("确认") { confirmEmergencyOverride() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 320, height: 240)
                .onAppear {
                    DispatchQueue.main.async { emergencyFocus = true }
                }
            }
    }

    private func confirmEmergencyOverride() {
        let ok = state.emergencyOverride(password: emergencyPasswordInput)
        if ok {
            state.showEmergencyOverrideSheet = false
            emergencyPasswordInput = ""
            emergencyPasswordError = false
        } else {
            emergencyPasswordError = true
        }
    }

    private func verifyPassword() {
        if KeychainPassword.verify(passwordInput) {
            passwordError = false
            passwordInput = ""
            state.showPasswordSheet = false
            state.pendingActionLabel = ""
            state.pendingToggleAction?()
        } else {
            passwordError = true
        }
    }

    // MARK: - Bottom control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Image(systemName: state.blockingEnabled ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(state.blockingEnabled ? Color.focusActive : Color.secondary)
                .frame(width: 24)

            if state.isProcessing {
                ProgressView().controlSize(.small)
                Text("处理中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if state.coolDownRemaining > 0 && !state.focusTimerActive {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("冷静期 · \(coolDownString(state.coolDownRemaining))")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            } else {
                Text(state.blockingEnabled ? "屏蔽中" : "已停止")
                    .font(.subheadline)
            }

            if state.blockingEnabled {
                listLockedBadge
            }

            Spacer()

            Button(action: {
                if state.delayedBlockActive {
                    state.blockNow()
                } else {
                    state.toggleBlocking()
                }
            }) {
                Text(controlButtonTitle)
                    .font(.subheadline)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: controlButtonColor))
            .disabled(state.isProcessing || state.isLocked || state.coolDownRemaining > 0)

            Button(action: { state.showSettingsSheet = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(AlwaysActiveBorderlessStyle())
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 56)
        .overlay(alignment: .top) { Divider() }
        .background(Color.secondary.opacity(0.07))
    }

    /// 延时屏蔽倒计时期间，主按钮变为「立即屏蔽」。
    private var controlButtonTitle: String {
        if state.delayedBlockActive { return "立即屏蔽" }
        return state.blockingEnabled ? "停止屏蔽" : "开启屏蔽"
    }

    private var controlButtonColor: Color {
        if state.delayedBlockActive { return .focusActive }
        return state.blockingEnabled ? .focusDanger : .focusAccent
    }

    private var listLockedBadge: some View {
        Label("屏蔽名单可增不可减", systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func statusBanner<Content: View>(
        icon: String,
        color: Color,
        actionTitle: String?,
        actionColor: Color?,
        actionDisabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder text: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            text()
            Spacer()
            if let actionTitle, let actionColor {
                Button(actionTitle) { action() }
                    .buttonStyle(AlwaysActiveBorderlessStyle(color: actionColor))
                    .font(.caption)
                    .disabled(actionDisabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private func remainingString(end: Date?) -> String {
    guard let end, end > Date() else { return "00:00" }
    let remaining = Int(end.timeIntervalSince(Date()))
    let mins = remaining / 60
    let secs = remaining % 60
    return String(format: "%02d:%02d", mins, secs)
}

private func coolDownString(_ remaining: TimeInterval) -> String {
    let total = Int(remaining)
    let mins = total / 60
    let secs = total % 60
    return String(format: "%02d:%02d", mins, secs)
}