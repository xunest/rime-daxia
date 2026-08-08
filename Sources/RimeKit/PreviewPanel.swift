import SwiftUI
import AppKit

/// 棋盘格：给预览区做底，透明度变化才看得出来
struct Checkerboard: Shape {
    var size: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cols = Int(rect.width / size) + 1
        let rows = Int(rect.height / size) + 1
        for r in 0..<rows {
            for c in 0..<cols where (r + c).isMultiple(of: 2) {
                p.addRect(CGRect(x: CGFloat(c) * size, y: CGFloat(r) * size,
                                 width: size, height: size))
            }
        }
        return p
    }
}

/// 常驻效果预览区：外观页与输入设置页共用
/// 改颜色、字体、字号、排版都能立刻看到结果
struct PreviewPanel: View {
    @EnvironmentObject var store: AppStore

    private var theme: Theme? {
        store.previewTheme(dark: store.previewDark)
    }

    /// 系统是否处于深色模式
    private var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("效果预览")
                    .font(.headline)
                Spacer()
                Picker("", selection: $store.previewDark) {
                    Text("浅色").tag(false)
                    Text("深色").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            .padding(.leading, 4)

            ZStack {
                // 棋盘格底：不透明度低于 100 时才能看出透出背景
                // 对比度要足够明显，否则看不出透明变化
                Checkerboard()
                    .fill(store.previewDark
                          ? Color.white.opacity(0.18)
                          : Color.black.opacity(0.14))
                    .background(store.previewDark
                                ? Color.black.opacity(0.9)
                                : Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let theme {
                    CandidatePreview(
                        theme: theme,
                        fontSize: store.fontSize,
                        labelFontSize: store.labelFontSize,
                        isLinear: store.isLinear,
                        showLabel: store.showLabel,
                        cornerRadius: store.cornerRadius,
                        lineSpacing: store.lineSpacing,
                        opacity: store.opacity,
                        pageSize: store.pageSize,
                        fontFace: store.fontFace,
                        inlinePreedit: store.inlinePreedit,
                        showPaging: store.showPaging,
                        hilitedCornerRadius: store.hilitedCornerRadius,
                        shadowSize: store.shadowSize,
                        borderPadding: store.borderPadding
                    )
                } else {
                    Text("未找到主题定义")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: previewHeight)

            // 深色配色只在系统切到深色时启用，容易被误认为设置无效
            HStack(spacing: 6) {
                Image(systemName: systemIsDark ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(systemIsDark ? .indigo : .orange)
                Text(systemIsDark
                     ? "系统当前为深色模式，输入法使用「深色」配色"
                     : "系统当前为浅色模式；深色配色要等系统切到深色才生效")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 4)
        }
    }

    /// 高度随字号、候选数、行距、留白变化，避免大字号或大留白被裁切
    private var previewHeight: CGFloat {
        let row = CGFloat(store.fontSize) + 16
        // 留白与阴影都会撑大候选窗，预留出来
        let chrome = CGFloat(store.borderPadding) * 2 + CGFloat(store.shadowSize) + 56
        if store.isLinear {
            return (store.inlinePreedit ? row : row * 2) + chrome
        }
        let rows = CGFloat(store.pageSize)
        return rows * row + CGFloat(store.lineSpacing) * (rows - 1)
            + (store.inlinePreedit ? 0 : row) + chrome
    }
}
