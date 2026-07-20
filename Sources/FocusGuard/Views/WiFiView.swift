import SwiftUI

struct WiFiView: View {
    @ObservedObject var state: AppState
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var showPasswordPrompt = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: state.wifiDisabled ? "network.slash" : "network")
                    .font(.system(size: 40))
                    .foregroundStyle(state.wifiDisabled ? .red : .green)

                Text(state.wifiDisabled ? "网络已拦截" : "网络正常")
                    .font(.title2.bold())

                Text(state.wifiDisabled
                     ? "DNS 已修改为无效地址，所有域名无法解析"
                     : "点击下方按钮将修改 DNS 为无效地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 6) {
                    HStack {
                        Text("当前状态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(state.wifiDisabled ? "已拦截" : "正常")
                            .font(.subheadline.bold())
                            .foregroundStyle(state.wifiDisabled ? .red : .green)
                    }
                    HStack {
                        Text("作用范围")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("系统级 DNS")
                            .font(.subheadline)
                    }
                    Text("通过将 DNS 服务器设为 127.0.0.1 阻止域名解析，从而切断网络访问。不影响局域网连接。恢复时需验证屏蔽密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                    Text("注意：若网络通过 DHCP 自动下发 DNS（常见于公司 Wi-Fi），路由器下发的 DNS 会覆盖系统设置，此拦截可能无效。建议在「系统设置 → 网络 → Wi-Fi → 详细信息 → DNS」中手动指定 DNS 后再使用。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    handleToggle()
                } label: {
                    Label(state.wifiDisabled ? "恢复网络" : "拦截网络",
                          systemImage: state.wifiDisabled ? "wifi" : "network.slash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: state.wifiDisabled ? .green : .red))
                .disabled(state.wifiBlocker.isProcessing || state.isLocked)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPasswordPrompt) {
            VStack(spacing: 16) {
                Text("输入密码以恢复网络")
                    .font(.headline)
                SecureField("输入密码", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { verifyAndEnableWiFi() }
                if passwordError {
                    Text("密码错误").foregroundStyle(.red).font(.caption)
                }
                HStack(spacing: 16) {
                    Button("取消") {
                        showPasswordPrompt = false
                        passwordInput = ""
                        passwordError = false
                    }
                    Button("确认") { verifyAndEnableWiFi() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300, height: 180)
        }
        .onAppear { state.wifiBlocker.checkStatusQuiet() }
    }

    private func handleToggle() {
        guard !state.isLocked else {
            state.lastError = "专注计时中，无法修改网络状态"
            return
        }
        if state.wifiDisabled {
            passwordInput = ""
            passwordError = false
            showPasswordPrompt = true
        } else {
            Task { await state.wifiBlocker.toggle() }
        }
    }

    private func verifyAndEnableWiFi() {
        if KeychainPassword.verify(passwordInput) {
            showPasswordPrompt = false
            passwordInput = ""
            passwordError = false
            Task { await state.wifiBlocker.toggle() }
        } else {
            passwordError = true
        }
    }
}
