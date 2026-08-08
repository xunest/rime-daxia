import SwiftUI
import AppKit

/// 外观页：只负责选皮肤，候选框细节调整在「输入设置」页
struct SkinView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""

    /// 预览的深浅切换由顶部常驻预览区控制，这里跟随它
    private var previewDark: Bool { store.previewDark }

    private var filteredThemes: [Theme] {
        guard !search.isEmpty else { return store.allThemes }
        return store.allThemes.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("外观")
                .font(.title)
                .fontWeight(.medium)

            colorSection
            skinSection
        }
    }

    // MARK: - 自定义配色
    private var colorSection: some View {
        GroupBox(label: Text("配色").font(.headline)) {
            VStack(spacing: 0) {
                SettingRow("自定义配色",
                           hint: "开启后直接调颜色，不再使用下方预设") {
                    Toggle("", isOn: Binding(
                        get: { store.useCustomColors },
                        set: { on in
                            // 首次开启时以当前预设为起点，避免从空白开始调
                            if on { store.seedCustomFromPresets() }
                            store.useCustomColors = on
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(Color.wxGreen)
                    .labelsHidden()
                }

                if store.useCustomColors {
                    Divider()
                    colorPickers
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "paintbrush.pointed")
                            .foregroundStyle(.secondary)
                        Text("正在编辑\(previewDark ? "深色" : "浅色")模式，切换上方开关可分别配置")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("取用下方选中预设的颜色") {
                            store.seedCustomFromPresets()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    /// 当前编辑的是深色还是浅色那一套
    private var editing: Binding<CustomScheme> {
        previewDark ? $store.customDark : $store.customLight
    }

    private var colorPickers: some View {
        VStack(spacing: 0) {
            SettingRow("候选窗背景") {
                ColorPicker("", selection: editing.back, supportsOpacity: false)
                    .labelsHidden()
            }
            Divider()
            SettingRow("候选字颜色") {
                ColorPicker("", selection: editing.candidateText, supportsOpacity: false)
                    .labelsHidden()
            }
            Divider()
            SettingRow("选中字颜色") {
                ColorPicker("", selection: editing.hilitedText, supportsOpacity: false)
                    .labelsHidden()
            }
            Divider()
            SettingRow("选中背景与候选窗同色",
                       hint: "勾选后选中项不画底色，只靠文字颜色区分") {
                Toggle("", isOn: editing.plainHilite)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            // 同色时下面的取色器无意义，隐藏避免误操作
            if !editing.wrappedValue.plainHilite {
                Divider()
                SettingRow("选中背景色") {
                    ColorPicker("", selection: editing.hilitedBack, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            Divider()
            SettingRow("序号与拼音颜色") {
                ColorPicker("", selection: editing.label, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    // MARK: - 皮肤网格
    private var skinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.useCustomColors
                     ? "预设（可作为自定义起点）"
                     : (previewDark ? "深色模式皮肤" : "浅色模式皮肤"))
                    .font(.headline)
                Spacer()
                TextField("搜索皮肤", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("\(filteredThemes.count)/\(store.allThemes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
                spacing: 10
            ) {
                ForEach(filteredThemes) { theme in
                    ThemeCardWX(
                        theme: theme,
                        isSelected: theme.id == (previewDark
                                                 ? store.selectedDarkThemeID
                                                 : store.selectedThemeID)
                    )
                    .onTapGesture {
                        if previewDark {
                            store.selectedDarkThemeID = theme.id
                        } else {
                            store.selectedThemeID = theme.id
                        }
                        // 自定义模式下点预设视为「取用这套颜色」
                        if store.useCustomColors {
                            let fallback: CustomScheme = previewDark ? .defaultDark : .defaultLight
                            editing.wrappedValue = CustomScheme(from: theme, fallback: fallback)
                        }
                    }
                }
            }
            .opacity(store.useCustomColors ? 0.75 : 1)
        }
    }
}

// MARK: - 通用设置行
struct SettingRow<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder let content: () -> Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            content()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
    }
}

// MARK: - 皮肤卡片
struct ThemeCardWX: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 模拟候选窗缩略图
            HStack(spacing: 4) {
                Text("1 好")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(rime: theme.hilitedCandidateTextColor) ?? .white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(rime: theme.hilitedCandidateBackColor) ?? .accentColor)
                    )
                Text("2 号")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(rime: theme.candidateTextColor) ?? .primary)
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(rime: theme.backColor) ?? Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(rime: theme.borderColor) ?? .clear, lineWidth: 1)
            )

            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.wxGreen)
                        .font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.wxGreen : Color.gray.opacity(0.15),
                              lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}
