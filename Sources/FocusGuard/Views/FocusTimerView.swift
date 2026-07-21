import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var state: AppState
    @State private var focusCustomMinutes: Int = 25
    @State private var delayedCustomMinutes: Int = 30
    @State private var configKind: FocusTimerState.Kind = .focus

    private let presets = [25, 30, 60]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if state.delayedBlockPendingAuth {
                    delayedBlockPendingView
                } else if let kind = state.activeTimerKind {
                    if kind == .focus {
                        focusRunningView
                    } else {
                        delayedBlockRunningView
                    }
                } else {
                    configPicker
                    if configKind == .focus {
                        focusConfigView
                    } else {
                        delayedBlockConfigView
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var configPicker: some View {
        Picker("计时类型", selection: $configKind) {
            Text("专注计时").tag(FocusTimerState.Kind.focus)
            Text("延时屏蔽").tag(FocusTimerState.Kind.delayedBlock)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var focusConfigView: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("专注计时")
                .font(.title2.bold())
            Text("开始计时后，所有屏蔽设置将被锁定，计时结束或紧急退出后才能修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            presetAndCustomView(minutes: $focusCustomMinutes)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if !state.blockingEnabled {
                Text("屏蔽未开启，请先开启屏蔽再使用专注计时")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                state.startFocusTimer(minutes: focusCustomMinutes)
            } label: {
                Label("开始计时", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .green))
            .disabled(focusCustomMinutes < 1 || state.delayedBlockActive || !state.blockingEnabled)
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockConfigView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("延时屏蔽")
                .font(.title2.bold())
            Text("开始计时后自由浏览，倒计时结束自动开启屏蔽。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if state.blockingEnabled {
                Text("屏蔽已开启，无需延时屏蔽")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                presetAndCustomView(minutes: $delayedCustomMinutes)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Text("到期锁屏、延长等选项见「设置 → 延时屏蔽」")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    state.startDelayedBlock(minutes: delayedCustomMinutes)
                } label: {
                    Label("开始计时", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .orange))
                .disabled(delayedCustomMinutes < 1 || state.blockingEnabled || state.focusTimerActive)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func presetAndCustomView(minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预设时长")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        minutes.wrappedValue = preset
                    } label: {
                        Text("\(preset) 分钟")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(AlwaysActiveButtonStyle(
                        color: selectedPreset(for: minutes.wrappedValue) == preset ? .blue : .gray))
                }
            }

            Text("自定义")
                .font(.headline)
            HStack {
                Stepper(value: minutes, in: 1...480, step: 5) {
                    TextField("分钟", value: minutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var focusRunningView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("专注计时中")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownString(at: context.date, end: state.focusTimerEnd))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }
            Text("所有屏蔽设置已锁定")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("本月紧急退出剩余 \(max(0, AppState.monthlyEmergencyQuota - state.emergencyUsesThisMonth)) 次")
                    .font(.subheadline)
                Text("紧急退出需输入密码，且每月最多 \(AppState.monthlyEmergencyQuota) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Button {
                state.showEmergencyOverrideSheet = true
            } label: {
                Label("紧急退出", systemImage: "xmark.shield")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .orange))
            .disabled(state.emergencyUsesThisMonth >= AppState.monthlyEmergencyQuota)
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockRunningView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("延时屏蔽倒计时")
                .font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownString(at: context.date, end: state.delayedBlockEnd))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }
            Text("倒计时结束后将自动开启屏蔽")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button {
                    state.blockNow()
                } label: {
                    Label("立即屏蔽", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .green))

                Button {
                    state.cancelDelayedBlock()
                } label: {
                    Label("取消计时", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(AlwaysActiveButtonStyle(color: .gray))
            }
        }
        .padding()
    }

    @ViewBuilder
    private var delayedBlockPendingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("屏蔽未生效")
                .font(.title2.bold())
            Text("到点了但未授权修改 hosts")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.delayedBlockRetryCount < 2 {
                Text("已延长 \(state.delayedBlockRetryCount) / 1 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("延长次数已用完")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let next = state.delayedBlockNextRetryAt, next > Date() {
                    Text("弹窗将在 \(Int(next.timeIntervalSinceNow))s 后再次出现")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("弹窗即将出现…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Button {
                state.presentExtendAlert()
            } label: {
                Label("立即打开弹窗", systemImage: "exclamationmark.bubble")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(AlwaysActiveButtonStyle(color: .orange))
        }
        .padding()
    }

    private func selectedPreset(for minutes: Int) -> Int? {
        presets.first { $0 == minutes }
    }

    private func countdownString(at now: Date, end: Date?) -> String {
        guard let end, end > now else { return "00:00" }
        let remaining = Int(end.timeIntervalSince(now))
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
