import SwiftUI

/// 极简冷静风设计系统：统一色板 + 统一卡片样式。
extension Color {
    /// 沉稳靛蓝：主强调色（开启屏蔽、选中态、主按钮）
    static let focusAccent = Color(red: 0.42, green: 0.47, blue: 0.72)
    /// 沉静青绿：屏蔽中/专注中状态
    static let focusActive = Color(red: 0.30, green: 0.60, blue: 0.55)
    /// 低饱和红：错误 / 紧急
    static let focusDanger = Color(red: 0.80, green: 0.35, blue: 0.32)
    /// 卡片底色（自适应明暗）
    static let focusCard = Color.secondary.opacity(0.12)
}

extension View {
    /// 统一卡片样式：圆角 10 + 内边距 + 自适应底色。
    func focusCard(cornerRadius: CGFloat = 10) -> some View {
        self
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}