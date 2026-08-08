import SwiftUI
import AppKit

extension Color {
    /// 从 Rime 颜色字符串构造（自动处理 BGR 顺序）
    init?(rime raw: String?) {
        guard let raw, let (r, g, b) = RimeColor.parse(raw) else { return nil }
        self.init(red: r, green: g, blue: b)
    }

    /// 转回 Rime 的 0xBBGGRR 写法
    var rimeHex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "0x%02X%02X%02X", b, g, r)
    }
}

/// 候选框预览：模拟真实输入时的样子
struct CandidatePreview: View {
    let theme: Theme
    let fontSize: Double
    let labelFontSize: Double
    let isLinear: Bool
    let showLabel: Bool
    let cornerRadius: Int
    let lineSpacing: Int
    let opacity: Int
    let pageSize: Int
    var fontFace: String = ""
    /// 拼音是否与候选同行显示
    var inlinePreedit: Bool = true
    /// 是否显示上下翻页箭头
    var showPaging: Bool = false
    /// 选中框圆角
    var hilitedCornerRadius: Int = 4
    /// 候选窗阴影大小
    var shadowSize: Int = 0
    /// 窗口内边距
    var borderPadding: Int = 4

    /// 候选词字体，空则用系统字体
    private func candidateFont(_ size: Double) -> Font {
        fontFace.isEmpty
            ? .system(size: size)
            : .custom(fontFace, size: size)
    }

    private let allCandidates = ["你好", "尼豪", "拟好", "呢好", "腻好", "泥好", "你号", "妮好", "尼号"]
    private let preedit = "ni hao"

    private var candidates: [String] {
        Array(allCandidates.prefix(pageSize))
    }

    private var back: Color {
        (Color(rime: theme.backColor) ?? Color(nsColor: .windowBackgroundColor))
            .opacity(Double(opacity) / 100.0)
    }
    private var candText: Color { Color(rime: theme.candidateTextColor) ?? .primary }
    private var hiBack: Color { Color(rime: theme.hilitedCandidateBackColor) ?? .accentColor }
    private var hiText: Color { Color(rime: theme.hilitedCandidateTextColor) ?? .white }
    private var labelC: Color { Color(rime: theme.labelColor) ?? .secondary }

    var body: some View {
        Group {
            if inlinePreedit {
                // 内嵌：拼音与候选同一行
                HStack(alignment: .center, spacing: 10) {
                    preeditText
                    candidateList
                }
            } else {
                // 独立：拼音单独占一行
                VStack(alignment: .leading, spacing: 6) {
                    preeditText
                    candidateList
                }
            }
        }
        .padding(.horizontal, CGFloat(borderPadding) + 8)
        .padding(.vertical, CGFloat(borderPadding) + 6)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius))
                .fill(back)
                .shadow(color: .black.opacity(shadowSize > 0 ? 0.35 : 0),
                        radius: CGFloat(shadowSize),
                        y: CGFloat(shadowSize) / 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius))
                .strokeBorder(Color(rime: theme.borderColor) ?? .clear, lineWidth: 1)
        )
        .fixedSize()
    }

    private var preeditText: some View {
        Text(preedit)
            .font(candidateFont(fontSize * 0.82))
            .foregroundStyle(labelC)
    }

    @ViewBuilder
    private var candidateList: some View {
        if isLinear {
            // 横排词间距 Rime 无对应字段，由内部 padding 决定，保持固定
            HStack(spacing: 8) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { idx, cand in
                    cell(idx: idx, text: cand)
                }
                if showPaging { pagingArrows }
            }
        } else {
            // line_spacing 只作用于竖排行距
            VStack(alignment: .leading, spacing: CGFloat(lineSpacing)) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { idx, cand in
                    cell(idx: idx, text: cand)
                }
                if showPaging {
                    pagingArrows
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// 上下翻页提示箭头，首页时上箭头置灰
    private var pagingArrows: some View {
        HStack(spacing: 2) {
            Image(systemName: "chevron.up")
                .foregroundStyle(labelC.opacity(0.35))
            Image(systemName: "chevron.down")
                .foregroundStyle(labelC)
        }
        .font(.system(size: labelFontSize * 0.8))
    }

    private func cell(idx: Int, text: String) -> some View {
        let selected = (idx == 0)
        return HStack(spacing: 3) {
            if showLabel {
                Text("\(idx + 1)")
                    .font(candidateFont(labelFontSize))
                    .foregroundStyle(selected ? hiText.opacity(0.85) : labelC)
            }
            Text(text)
                .font(candidateFont(fontSize))
                .foregroundStyle(selected ? hiText : candText)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(hilitedCornerRadius))
                .fill(selected ? hiBack : .clear)
        )
    }
}
