import SwiftUI

// MARK: - 微信风格配色
extension Color {
    static let wxGreen = Color(red: 0.04, green: 0.76, blue: 0.41)   // 微信绿
    static let wxBg = Color(nsColor: .init(white: 0.96, alpha: 1))     // 左侧背景灰
    static let wxCard = Color.white
    static let wxText = Color(nsColor: .controlTextColor)
    static let wxSecondary = Color.secondary
}

// MARK: - 导航项
enum NavItem: String, CaseIterable, Identifiable {
    case skin = "外观"
    case general = "输入设置"
    case phrase = "常用语"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .skin: return "paintpalette.fill"
        case .general: return "keyboard.fill"
        case .phrase: return "text.bubble.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - 主窗口
struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var nav = NavItem.skin
    @State private var showResetConfirm = false

    var body: some View {
        if store.installed {
            mainContent
                .frame(minWidth: 920, minHeight: 620)
        } else {
            // 引擎或词库缺失，走引导安装；资源已内嵌在 app 内。
            // 安装页只有一个按钮，用主界面那个 920 的尺寸会显得空旷，
            // 所以单独给一个紧凑窗口。
            SetupView()
                .frame(width: 500, height: 420)
        }
    }

    private var mainContent: some View {
        HSplitView {
            // 左侧导航栏（微信风格：绿底白字选中）
            VStack(spacing: 4) {
                ForEach(NavItem.allCases) { item in
                    Button {
                        nav = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(nav == item ? Color.wxGreen : Color.clear)
                        )
                        .foregroundColor(nav == item ? .white : Color.wxText)
                    }
                    .buttonStyle(.plain)
                    // 导航项靠点击切换，不参与键盘焦点
                    // 否则启动时首项会被套上系统焦点环，看着像误选中
                    .focusable(false)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(width: 180)
            .background(Color.wxBg)

            // 右侧内容区
            VStack(spacing: 0) {
                // 外观与输入设置都影响候选窗，预览常驻在顶部
                if nav == .skin || nav == .general {
                    PreviewPanel()
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    Divider()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch nav {
                        case .skin:    SkinView()
                        case .general: GeneralView()
                        case .phrase:  PhraseView()
                        case .about:   AboutView()
                        }
                    }
                    .padding(24)
                }

                Divider()

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.wxBg.opacity(0.5))
            }
            // HSplitView 会按子视图最小宽度压缩，不给下限会把预览区挤成窄条
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !store.toast.isEmpty {
                Label(store.toast, systemImage: store.toastIsError
                      ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(store.toastIsError ? .red : Color.wxGreen)
                    .lineLimit(2)
            }

            Spacer()

            if nav == .skin || nav == .general {
                Button("恢复默认") {
                    showResetConfirm = true
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Button("保存") {
                    if nav == .skin { store.applyAppearance() }
                    else { store.applyGeneral() }
                }
                .buttonStyle(.bordered)
            }

            Button {
                if nav == .skin { store.applyAppearance() }
                if nav == .general { store.applyGeneral() }
                store.deploy()
            } label: {
                if store.config.isDeploying {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("部署中")
                    }
                } else {
                    Text("应用并部署")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.wxGreen)
            .disabled(store.config.isDeploying)
        }
        .alert("恢复默认配置？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .destructive) { store.resetToDefaults() }
        } message: {
            Text("皮肤和输入设置会还原为最初的 macOS 风格配置：横排候选、7 个候选、字号 17、无模糊音。自定义短语不受影响。")
        }
    }
}

