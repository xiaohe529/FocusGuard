import SwiftUI

struct WebsiteListView: View {
    @ObservedObject var state: AppState
    @State private var newDomain = ""
    @State private var revertingRuleID: UUID? = nil
    @State private var pendingDeleteID: UUID? = nil

    let suggestions = ["facebook.com","twitter.com","youtube.com","reddit.com","instagram.com","tiktok.com","linkedin.com","bilibili.com","douyin.com","weibo.com"]

    var filteredSuggestions: [String] {
        suggestions.filter { s in
            !state.blockRules.contains(where: { $0.name == s && $0.type == .website })
        }
    }

    var websiteRules: [BlockRule] {
        state.blockRules.filter { $0.type == .website }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Input row
            HStack {
                TextField("输入域名，如 weibo.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addDomain() }
                    .disabled(state.isLocked)
                Button("添加", action: addDomain)
                    .buttonStyle(AlwaysActiveButtonStyle(color: .blue))
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || state.isLocked)
            }

            // Quick add pills
            if !filteredSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(filteredSuggestions, id: \.self) { s in
                            Button(s) {
                                addSuggestion(s)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Divider()

            // Rule list
            if websiteRules.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($state.blockRules) { $rule in
                            if rule.type == .website {
                                ruleRow($rule)
                            }
                        }
                    }
                }
            }
        }
        .alert("删除屏蔽规则？", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeleteID = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID {
                    let rule = state.blockRules.first { $0.id == id }
                    state.blockRules.removeAll { $0.id == id }
                    pendingDeleteID = nil
                    if let rule { FocusLogger.info("Deleted website rule: \(rule.name)") }
                    Task { _ = await state.save() }
                }
            }
        } message: {
            if let id = pendingDeleteID, let r = state.blockRules.first(where: { $0.id == id }) {
                Text("确定要删除「\(r.name)」吗？此操作不可撤销。")
            } else {
                Text("确定要删除这条规则吗？")
            }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "globe.badge.xmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("还没有添加网站")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("输入域名或点击下方常用网站快速添加")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder
    private func ruleRow(_ rule: Binding<BlockRule>) -> some View {
        let r = rule.wrappedValue
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Toggle(isOn: rule.enabled) {
                Text(r.name)
                    .font(.body)
                    .lineLimit(1)
            }
            .toggleStyle(AlwaysActiveSwitchStyle())
            .disabled(state.isLocked)
            Spacer()
            Button {
                pendingDeleteID = r.id
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.tertiary)
                    .padding(4)
            }
            .buttonStyle(AlwaysActiveBorderlessStyle())
            .disabled(state.isLocked)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .onChange(of: rule.enabled.wrappedValue) { oldValue, newState in
            // Skip if this change is a revert from a failed/cancelled operation
            if revertingRuleID == r.id {
                revertingRuleID = nil
                return
            }

            let ruleID = r.id

            if !newState {
                // Disabling (ON→OFF): requires FocusGuard password
                if state.hasPassword {
                    // Revert toggle, ask password
                    revertingRuleID = ruleID
                    rule.enabled.wrappedValue = oldValue
                    state.pendingToggleAction = {
                        // Password verified — apply the disable
                        revertingRuleID = ruleID
                        rule.enabled.wrappedValue = newState
                        Task {
                            let success = await state.save()
                            if !success {
                                // Admin dialog cancelled — revert to ON
                                revertingRuleID = ruleID
                                rule.enabled.wrappedValue = oldValue
                            }
                        }
                    }
                    state.showPasswordSheet = true
                } else {
                    // No password set — save directly
                    Task {
                        let success = await state.save()
                        if !success {
                            revertingRuleID = ruleID
                            rule.enabled.wrappedValue = oldValue
                        }
                    }
                }
            } else {
                // Enabling (OFF→ON): no FocusGuard password, save directly
                Task {
                    let success = await state.save()
                    if !success {
                        // Admin dialog cancelled — revert to OFF
                        revertingRuleID = ruleID
                        rule.enabled.wrappedValue = oldValue
                    }
                }
            }
        }
        Divider()
            .padding(.leading, 28)
    }

    func addDomain() {
        guard !state.isLocked else {
            state.lastError = "专注计时中，无法修改屏蔽规则"
            return
        }
        let clean = newDomain.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty,
              !state.blockRules.contains(where: { $0.name == clean && $0.type == .website })
        else { return }
        state.blockRules.append(BlockRule(name: clean, type: .website))
        Task { _ = await state.save() }
        newDomain = ""
    }

    func addSuggestion(_ s: String) {
        guard !state.isLocked else {
            state.lastError = "专注计时中，无法修改屏蔽规则"
            return
        }
        guard !state.blockRules.contains(where: { $0.name == s && $0.type == .website })
        else { return }
        state.blockRules.append(BlockRule(name: s, type: .website))
        Task { _ = await state.save() }
    }
}
