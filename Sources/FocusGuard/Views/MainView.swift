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

    let tabLabels = ["网站屏蔽", "App屏蔽", "网络控制", "专注计时"]
    let tabIcons = ["globe", "xmark.app", "network.slash", "timer"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — fixed at top
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        selectedTab = i
                    } label: {
                        Label(tabLabels[i], systemImage: tabIcons[i])
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == i ? .primary : .secondary)
                    .background(selectedTab == i ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if selectedTab == i {
                            Rectangle().fill(.blue).frame(height: 2)
                        }
                    }
                }
            }
            .padding(.top, 16)

            Divider()

            // Focus-timer / delayed-block banner
            if state.focusTimerActive {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.red)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("专注计时中 · 剩余 \(remainingString(end: state.focusTimerEnd))")
                            .font(.subheadline)
                    }
                    Spacer()
                    Button("紧急退出") { state.showEmergencyOverrideSheet = true }
                        .buttonStyle(AlwaysActiveBorderlessStyle(color: .orange))
                        .font(.caption)
                        .disabled(state.emergencyUsesThisMonth >= AppState.monthlyEmergencyQuota)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 4)
            } else if state.delayedBlockActive {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("延时屏蔽倒计时 · 剩余 \(remainingString(end: state.delayedBlockEnd)) · 到点自动屏蔽")
                            .font(.subheadline)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 4)
            } else if state.delayedBlockPendingAuth {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text("屏蔽未生效 · 到点未授权")
                        .font(.subheadline)
                    Spacer()
                    Button("去授权") { selectedTab = 3 }
                        .buttonStyle(AlwaysActiveBorderlessStyle(color: .red))
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .padding(.top, 4)
            }

            // Scrollable content
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: WebsiteListView(state: state)
                    case 1: AppListView(state: state)
                    case 2: WiFiView(state: state)
                    default: FocusTimerView(state: state)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

            // Password not set reminder
            if state.blockingEnabled && !state.hasPassword {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundStyle(.orange)
                    Text("未设置屏蔽密码，点击「停止屏蔽」无需验证即可关闭。建议设置密码增加操作摩擦，防止一时冲动。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("设置") { state.showSettingsSheet = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
            }

            // Error banner
            if let error = state.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("清除") { state.lastError = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
            }

            Divider()

            // Control bar
            HStack(spacing: 8) {
                Image(systemName: state.blockingEnabled ? "lock.shield.fill" : "lock.shield")
                    .foregroundStyle(state.blockingEnabled ? .red : .secondary)
                if state.isProcessing {
                    ProgressView().controlSize(.small)
                    Text("处理中…").font(.subheadline)
                } else {
                    Text(state.blockingEnabled ? "屏蔽中" : "已停止")
                        .font(.subheadline)
                }
                Spacer()
                Button(action: { state.toggleBlocking() }) {
                    Text(state.blockingEnabled ? "停止屏蔽" : "开启屏蔽")
                        .font(.subheadline)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: state.blockingEnabled ? .red : .green))
                .disabled(state.isProcessing || state.isLocked || state.delayedBlockActive)
                // Helper status dot — only show when not installed (avoid clutter when everything's fine)
                if !state.helperInstalled {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                        .help("后台助手未安装，首次操作将请求授权")
                }
                Button(action: { state.showSettingsSheet = true }) {
                    Image(systemName: "gearshape")
                        .font(.subheadline)
                }
                .buttonStyle(AlwaysActiveBorderlessStyle())
                .help("设置")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 500, minHeight: 500, alignment: .top)
        .sheet(isPresented: $state.showPasswordSheet, onDismiss: {
                passwordInput = ""
                passwordError = false
                state.pendingToggleAction = nil
                state.lastError = nil
            }) {
                VStack(spacing: 16) {
                    Text("输入密码解除屏蔽")
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

    private func remainingString(end: Date?) -> String {
        guard let end, end > Date() else { return "00:00" }
        let remaining = Int(end.timeIntervalSince(Date()))
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
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
            state.pendingToggleAction?()
        } else {
            passwordError = true
        }
    }
}