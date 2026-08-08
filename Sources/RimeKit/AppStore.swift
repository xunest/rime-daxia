import SwiftUI
import Combine

/// 全局状态：负责在界面与 YAML 文件之间同步
final class AppStore: ObservableObject {
    let config = RimeConfig()
    let library = ThemeLibrary(yamlContent: builtinThemesYAML)

    // 外观
    @Published var selectedThemeID: String = "macos_light"
    @Published var selectedDarkThemeID: String = "macos_dark"
    @Published var fontSize: Double = 17
    @Published var labelFontSize: Double = 14
    @Published var fontFace: String = ""          // 空表示系统默认
    @Published var layout: CandidateLayout = .horizontal
    @Published var showLabel: Bool = true
    @Published var opacity: Int = 100             // 100 为不透明
    @Published var cornerRadius: Int = 8
    @Published var hilitedCornerRadius: Int = 4   // 选中框圆角
    @Published var shadowSize: Int = 0            // 候选窗阴影
    @Published var borderPadding: Int = 4         // 窗口留白（border_width/height）
    @Published var lineSpacing: Int = 5
    @Published var inlinePreedit: Bool = true     // 拼音内嵌在光标处
    @Published var showPaging: Bool = false       // 显示翻页箭头

    // 自定义配色：开启后用 CustomScheme.id 这套方案，颜色由取色器决定
    @Published var useCustomColors: Bool = false
    @Published var customLight = CustomScheme.defaultLight
    @Published var customDark = CustomScheme.defaultDark

    // 常用设置
    @Published var pageSize: Int = 7
    @Published var fuzzyZhCh: Bool = false      // z/zh c/ch s/sh
    @Published var fuzzyNL: Bool = false        // n/l
    @Published var fuzzyAngAn: Bool = false     // ang/an eng/en ing/in
    @Published var fuzzyFH: Bool = false        // f/h
    @Published var fuzzyGK: Bool = false        // g/k

    // 标点与输入行为
    @Published var asciiPunct: Bool = false     // 中文状态下用英文标点
    @Published var pairedSymbols: Bool = true   // 成对符号自动补齐
    @Published var traditionalDefault: Bool = false  // 默认输出繁体
    @Published var emojiOn: Bool = true         // Emoji 候选
    @Published var commaPaging: Bool = true     // 逗号句号翻页

    // 状态提示
    @Published var toast: String = ""
    @Published var toastIsError = false

    /// 安装是否就绪。安装状态要查文件系统，不能每次渲染都查，
    /// 且 RimeConfig 是嵌套的 ObservableObject，它的变更不会刷新
    /// 观察 AppStore 的视图，所以在这里存一份并显式刷新。
    @Published var installed: Bool = Installer.isFullyInstalled

    /// 重新检测安装状态，安装完成后调用
    func refreshInstallState() {
        installed = Installer.isFullyInstalled
    }

    /// 预览区当前看的是深色还是浅色，外观页与输入设置页共享
    @Published var previewDark: Bool = false

    /// 用户配置里已存在的主题（可能是自己写的）
    @Published var userThemes: [Theme] = []

    /// 预览按横排渲染，由排版模式派生
    var isLinear: Bool { layout.isLinear }

    var allThemes: [Theme] {
        // 用户自定义主题排在前面，内置库在后；ID 重复时以用户的为准
        let userIDs = Set(userThemes.map(\.id))
        return userThemes + library.themes.filter { !userIDs.contains($0.id) }
    }

    var currentTheme: Theme? {
        allThemes.first { $0.id == selectedThemeID }
    }

    /// 预览用的主题：自定义模式下直接由取色器合成
    func previewTheme(dark: Bool) -> Theme? {
        if useCustomColors {
            return dark
                ? customDark.asTheme(id: CustomScheme.darkID, name: "自定义-深色")
                : customLight.asTheme(id: CustomScheme.lightID, name: "自定义-浅色")
        }
        let id = dark ? selectedDarkThemeID : selectedThemeID
        return allThemes.first { $0.id == id }
    }

    /// 把当前选中的预设颜色灌进取色器，作为微调起点
    func seedCustomFromPresets() {
        if let light = allThemes.first(where: { $0.id == selectedThemeID }) {
            customLight = CustomScheme(from: light, fallback: .defaultLight)
        }
        if let dark = allThemes.first(where: { $0.id == selectedDarkThemeID }) {
            customDark = CustomScheme(from: dark, fallback: .defaultDark)
        }
    }

    init() {
        loadFromDisk()
    }

    // MARK: - 读取现有配置

    func loadFromDisk() {
        guard config.rimeDirExists else { return }

        let squirrelText = config.read(.squirrel)
        let squirrel = YAMLLineEditor(content: squirrelText)

        // 解析用户已有的主题定义
        userThemes = ThemeLibrary(yamlContent: squirrelText).themes

        if let v = squirrel.value(forPath: "style/color_scheme") {
            selectedThemeID = v
        }
        if let v = squirrel.value(forPath: "style/color_scheme_dark") {
            selectedDarkThemeID = v
        }

        // 上次用的是自定义配色，就把取色器恢复成保存过的颜色
        useCustomColors = (selectedThemeID == CustomScheme.lightID)
        if useCustomColors {
            if let t = userThemes.first(where: { $0.id == CustomScheme.lightID }) {
                customLight = CustomScheme(from: t, fallback: .defaultLight)
            }
            if let t = userThemes.first(where: { $0.id == CustomScheme.darkID }) {
                customDark = CustomScheme(from: t, fallback: .defaultDark)
            }
            // 列表里的选中态回退到默认预设，避免显示成自定义方案本身
            selectedThemeID = "macos_light"
            selectedDarkThemeID = "macos_dark"
        }

        // 字号、横竖排是全局设置，不从主题内读取
        // 这样换主题不会改变用户之前的字号和排版习惯
        if let v = squirrel.value(forPath: "style/font_point"), let n = Double(v) {
            fontSize = n
        } else {
            fontSize = 17
        }
        if let v = squirrel.value(forPath: "style/label_font_point"), let n = Double(v) {
            labelFontSize = n
        }
        if let v = squirrel.value(forPath: "style/font_face") {
            // 配置里的字体本机可能没装，此时回退到「跟随皮肤」
            fontFace = FontLibrary.chineseFamilies.contains(v) ? v : ""
        } else {
            fontFace = ""
        }
        layout = CandidateLayout.from(
            listLayout: squirrel.value(forPath: "style/candidate_list_layout"),
            textOrientation: squirrel.value(forPath: "style/text_orientation")
        )
        if let v = squirrel.value(forPath: "style/corner_radius"), let n = Int(v) {
            cornerRadius = n
        }
        if let v = squirrel.value(forPath: "style/hilited_corner_radius"), let n = Int(v) {
            hilitedCornerRadius = n
        }
        if let v = squirrel.value(forPath: "style/shadow_size"), let n = Int(v) {
            shadowSize = n
        }
        // 留白用 border_width，负值是皮肤的特殊写法，读成 0
        if let v = squirrel.value(forPath: "style/border_width"), let n = Int(v) {
            borderPadding = max(n, 0)
        }
        if let v = squirrel.value(forPath: "style/line_spacing"), let n = Int(v) {
            lineSpacing = n
        }
        if let v = squirrel.value(forPath: "style/inline_preedit") {
            inlinePreedit = (v == "true")
        }
        if let v = squirrel.value(forPath: "style/show_paging") {
            showPaging = (v == "true")
        }
        // 序号显隐：candidate_format 里有 %c 就是显示
        if let v = squirrel.value(forPath: "style/candidate_format") {
            showLabel = v.contains("%c")
        } else {
            showLabel = true
        }

        // 透明度从当前主题的 back_color alpha 通道反推
        opacity = readOpacity(from: squirrelText)

        let defaultsText = config.read(.defaults)
        let defaults = YAMLLineEditor(content: defaultsText)
        if let v = defaults.value(forPath: "menu/page_size"), let n = Int(v) {
            pageSize = n
        }

        loadFuzzyState()
        loadPunctState()
    }

    /// 从选中主题的 back_color 反推透明度
    private func readOpacity(from text: String) -> Int {
        let lib = ThemeLibrary(yamlContent: text)
        let id = useCustomColors ? CustomScheme.lightID : selectedThemeID
        guard let theme = lib.themes.first(where: { $0.id == id }),
              let back = theme.backColor else { return 100 }

        var hex = back.replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        guard hex.count == 8 else { return 100 }

        hex = String(hex.prefix(2))
        guard let alpha = UInt32(hex, radix: 16) else { return 100 }
        return Int((Double(alpha) / 255.0 * 100).rounded())
    }

    /// 读取标点与输入行为状态
    private func loadPunctState() {
        let text = config.read(.schema)
        let editor = YAMLLineEditor(content: text)

        if let v = editor.value(forPath: "switches/@ascii_punct/reset") {
            asciiPunct = (v == "1")
        }
        if let v = editor.value(forPath: "switches/@traditionalization/reset") {
            traditionalDefault = (v == "1")
        }
        if let v = editor.value(forPath: "switches/@emoji/reset") {
            emojiOn = (v == "1")
        } else {
            emojiOn = true   // 雾凇默认开启 emoji
        }
    }

    // MARK: - 写入

    /// 「外观」页保存：只改皮肤，不动候选窗设置
    func applyAppearance() {
        do {
            try writeTheme()
            showToast("皮肤已保存，点「应用并部署」生效")
        } catch {
            showToast("保存失败：\(error.localizedDescription)", error: true)
        }
    }

    /// 只写皮肤相关：color_scheme 及必要的主题定义块
    private func writeTheme() throws {
        var text = config.read(.squirrel)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "# 鼠须管外观配置\npatch:\n"
        }

        if useCustomColors {
            // 自定义配色：每次都用最新取色重写这两套方案块
            text = upsertThemeBlock(
                customLight.yamlBlock(id: CustomScheme.lightID, name: "自定义-浅色"),
                themeID: CustomScheme.lightID, into: text)
            text = upsertThemeBlock(
                customDark.yamlBlock(id: CustomScheme.darkID, name: "自定义-深色"),
                themeID: CustomScheme.darkID, into: text)
        } else {
            // 若选的是内置主题且用户配置里还没有它的定义，先把定义块补进去
            let hasDefinition = ThemeLibrary(yamlContent: text).themes.contains { $0.id == selectedThemeID }
            if !hasDefinition, let block = library.rawBlocks[selectedThemeID] {
                text = insertThemeBlock(block, themeID: selectedThemeID, into: text)
            }
            let hasDarkDef = ThemeLibrary(yamlContent: text).themes.contains { $0.id == selectedDarkThemeID }
            if !hasDarkDef, selectedDarkThemeID != selectedThemeID,
               let block = library.rawBlocks[selectedDarkThemeID] {
                text = insertThemeBlock(block, themeID: selectedDarkThemeID, into: text)
            }
        }

        try config.write(themeResult(from: text), to: .squirrel)
    }

    /// 皮肤写入的纯计算部分，便于自测
    func themeResult(from text: String) -> String {
        var editor = YAMLLineEditor(content: text)
        let lightID = useCustomColors ? CustomScheme.lightID : selectedThemeID
        let darkID = useCustomColors ? CustomScheme.darkID : selectedDarkThemeID
        editor.setValue(lightID, forPath: "style/color_scheme")
        editor.setValue(darkID, forPath: "style/color_scheme_dark")

        // 新皮肤自带的排版字段要注释掉，否则会覆盖用户在「输入设置」里的选择
        var result = neutralizeThemeOverrides(editor.content)

        // 沿用当前的透明度设置，让新皮肤跟已有透明度一致
        if opacity < 100 {
            result = applyOpacityToThemes(result, opacity: opacity)
        }
        return result
    }

    /// 只写候选窗设置：字号、排版、透明度等，与皮肤无关
    private func writeCandidateStyle() throws {
        var text = config.read(.squirrel)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "# 鼠须管外观配置\npatch:\n"
        }
        try config.write(candidateStyleResult(from: text), to: .squirrel)
    }

    /// 候选窗写入的纯计算部分，便于自测
    func candidateStyleResult(from text: String) -> String {
        var editor = YAMLLineEditor(content: text)
        editor.setValue(String(Int(fontSize)), forPath: "style/font_point")
        editor.setValue(String(Int(labelFontSize)), forPath: "style/label_font_point")
        editor.setValue(layout.listLayout, forPath: "style/candidate_list_layout")
        editor.setValue(layout.textOrientation, forPath: "style/text_orientation")
        editor.setValue(String(cornerRadius), forPath: "style/corner_radius")
        editor.setValue(String(hilitedCornerRadius), forPath: "style/hilited_corner_radius")
        editor.setValue(String(shadowSize), forPath: "style/shadow_size")
        // Rime 用宽高两个字段控制窗口内边距，一起写保证四边一致
        editor.setValue(String(borderPadding), forPath: "style/border_width")
        editor.setValue(String(borderPadding), forPath: "style/border_height")
        editor.setValue(String(lineSpacing), forPath: "style/line_spacing")
        editor.setValue(inlinePreedit ? "true" : "false", forPath: "style/inline_preedit")
        editor.setValue(showPaging ? "true" : "false", forPath: "style/show_paging")
        editor.setValue(opacity < 100 ? "true" : "false", forPath: "style/translucency")

        // 序号显隐由 candidate_format 决定：%c 是序号占位符，去掉即不显示
        // 用 1/6 em 空格 U+2005 分隔，与主流皮肤写法一致
        editor.setValue(showLabel ? "\"%c\\u2005%@\"" : "\"%@\"",
                        forPath: "style/candidate_format")

        // 字体：非空才接管；空表示跟随皮肤自带字体
        if !fontFace.isEmpty {
            editor.setValue("\"\(fontFace)\"", forPath: "style/font_face")
        }

        // 主题内的排版字段优先级更高，必须注释掉才能让全局设置生效
        // 字体只在用户指定了才接管，否则保留皮肤自己的 font_face
        var result = neutralizeThemeOverrides(editor.content,
                                              includeFontFace: !fontFace.isEmpty)
        result = applyOpacityToThemes(result, opacity: opacity)
        return result
    }

    /// 给当前选中的两套主题的 back_color 加上 alpha 通道
    /// Rime 颜色为 0xAABBGGRR，AA 是透明度
    private func applyOpacityToThemes(_ text: String, opacity: Int) -> String {
        let alpha = UInt32(Double(opacity) / 100.0 * 255.0)
        let alphaHex = String(format: "%02X", alpha)

        var lines = text.components(separatedBy: "\n")
        var inTargetTheme = false
        var themeIndent = -1

        // 自定义模式下要改的是自定义方案，否则是选中的预设
        let targetIDs = useCustomColors
            ? [CustomScheme.lightID, CustomScheme.darkID]
            : [selectedThemeID, selectedDarkThemeID]

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            // 进入目标主题块
            for id in targetIDs {
                if trimmed == "preset_color_schemes/\(id):" || trimmed == "\(id):" {
                    inTargetTheme = true
                    themeIndent = indent
                    break
                }
            }
            if inTargetTheme && indent <= themeIndent && !trimmed.hasPrefix("#")
                && !trimmed.hasSuffix(":") {
                inTargetTheme = false
            }

            guard inTargetTheme, trimmed.hasPrefix("back_color:") else { continue }

            // 提取原色值，替换成带 alpha 的 8 位形式
            guard let raw = YAMLLineEditor.extractValue(from: trimmed) else { continue }
            var hex = raw.replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\"", with: "")
            if hex.count == 8 { hex = String(hex.suffix(6)) }   // 已有 alpha 则替换
            guard hex.count == 6 else { continue }

            lines[i] = YAMLLineEditor.replaceValue(in: line, with: "0x\(alphaHex)\(hex)")
        }
        return lines.joined(separator: "\n")
    }

    /// 供自测调用
    func testNeutralize(_ text: String) -> String {
        neutralizeThemeOverrides(text)
    }

    func testApplyOpacity(_ text: String, opacity: Int) -> String {
        applyOpacityToThemes(text, opacity: opacity)
    }

    func testFuzzyRules() -> String {
        fuzzyRules().joined(separator: "\n")
    }

    /// 把主题块内会覆盖全局排版设置的字段注释掉
    /// 只处理排版相关（布局、方向、字号），颜色定义完全不动
    ///
    /// 需要同时兼容两种写法：
    ///   嵌套式  preset_color_schemes:  →  macos_light:  →  字段（缩进 6）
    ///   扁平式  preset_color_schemes/macos_light:      →  字段（缩进 4）
    private func neutralizeThemeOverrides(_ text: String,
                                          includeFontFace: Bool = false) -> String {
        // candidate_format 决定序号显隐，label_font_point 决定序号字号，
        // 皮肤里若带这两项会盖掉全局设置（不少皮肤用 label_font_point: 1 来隐藏序号）
        var conflictKeys = ["candidate_list_layout", "text_orientation", "horizontal",
                            "font_point", "label_font_point", "candidate_format",
                            // 圆角、留白、阴影、行距皮肤里也常带，会盖掉全局设置
                            "corner_radius", "hilited_corner_radius", "line_spacing",
                            "border_width", "border_height", "shadow_size"]
        // 字体只在用户明确指定时才中和，否则让皮肤自带字体继续生效
        if includeFontFace {
            conflictKeys += ["font_face", "label_font_face",
                             "candidate_font_face", "comment_font_face"]
        }
        var lines = text.components(separatedBy: "\n")

        // 先标记出哪些行处在主题定义块内部
        var insideTheme = [Bool](repeating: false, count: lines.count)
        var themeBlockIndent = -1   // 主题块内字段的基准缩进，-1 表示当前不在块内

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            // 扁平写法：preset_color_schemes/xxx:
            if trimmed.hasPrefix("preset_color_schemes/") && trimmed.hasSuffix(":") {
                themeBlockIndent = indent
                continue
            }
            // 嵌套写法：preset_color_schemes:
            if trimmed.hasPrefix("preset_color_schemes:") {
                themeBlockIndent = indent
                continue
            }

            guard themeBlockIndent >= 0 else { continue }

            // 缩进回到基准或更浅，说明离开了主题区
            if indent <= themeBlockIndent && !trimmed.hasPrefix("#") {
                themeBlockIndent = -1
                continue
            }
            insideTheme[i] = true
        }

        for (i, line) in lines.enumerated() where insideTheme[i] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }

            let indent = line.prefix(while: { $0 == " " }).count
            for key in conflictKeys where trimmed.hasPrefix("\(key):") {
                lines[i] = "\(String(repeating: " ", count: indent))# \(trimmed)   # 由 RimeKit 接管为全局设置"
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 写入方案块：已存在则整块替换，不存在则插入
    /// 自定义配色每次保存都要覆盖旧值，不能只在缺失时插入
    func upsertThemeBlock(_ block: String, themeID: String, into text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        // 找到已有块的范围：`xxx:` 或 `preset_color_schemes/xxx:`
        var startIdx: Int?
        var blockIndent = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "\(themeID):" || t == "preset_color_schemes/\(themeID):" {
                startIdx = i
                blockIndent = line.prefix(while: { $0 == " " }).count
                break
            }
        }

        guard let start = startIdx else {
            return insertThemeBlock(block, themeID: themeID, into: text)
        }

        // 块的结束：下一个缩进不深于块头的非空行
        var end = start + 1
        while end < lines.count {
            let line = lines[end]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { end += 1; continue }
            if line.prefix(while: { $0 == " " }).count <= blockIndent { break }
            end += 1
        }

        let shifted = reindent(block, from: 4, to: blockIndent)
        lines.replaceSubrange(start..<end, with: shifted.components(separatedBy: "\n"))
        return lines.joined(separator: "\n")
    }

    /// 把内置主题的定义块插入到 preset_color_schemes: 段下
    private func insertThemeBlock(_ block: String, themeID: String, into text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        // 找 preset_color_schemes: 所在行
        var presetIdx: Int?
        var presetIndent = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("preset_color_schemes:") {
                presetIdx = i
                presetIndent = line.prefix(while: { $0 == " " }).count
                break
            }
        }

        // 内置库里的块缩进是 4 空格（在 patch/preset_color_schemes 下）
        let sourceIndent = 4

        if let idx = presetIdx {
            let targetIndent = presetIndent + 2
            let shifted = reindent(block, from: sourceIndent, to: targetIndent)
            lines.insert(contentsOf: shifted.components(separatedBy: "\n"), at: idx + 1)
        } else {
            // 没有 preset_color_schemes 段，在 patch: 下新建
            var patchIdx: Int?
            for (i, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("patch:") {
                    patchIdx = i
                    break
                }
            }
            let shifted = reindent(block, from: sourceIndent, to: 4)
            let newBlock = ["  preset_color_schemes:"] + shifted.components(separatedBy: "\n")
            if let pi = patchIdx {
                lines.insert(contentsOf: newBlock, at: pi + 1)
            } else {
                lines.append("patch:")
                lines.append(contentsOf: newBlock)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 整块调整缩进
    private func reindent(_ block: String, from: Int, to: Int) -> String {
        let delta = to - from
        if delta == 0 { return block }
        return block.components(separatedBy: "\n").map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if delta > 0 {
                return String(repeating: " ", count: delta) + line
            } else {
                let cur = line.prefix(while: { $0 == " " }).count
                let drop = min(-delta, cur)
                return String(line.dropFirst(drop))
            }
        }.joined(separator: "\n")
    }

    /// 应用常用设置
    func applyGeneral() {
        // 候选数写入 default.custom.yaml
        var text = config.read(.defaults)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "# 鼠须管用户配置\npatch:\n"
        }
        var editor = YAMLLineEditor(content: text)
        editor.setValue(String(pageSize), forPath: "menu/page_size")

        do {
            try config.write(editor.content, to: .defaults)
            // 候选窗样式（字号、排版、透明度）也在本页调整，一并保存
            try writeCandidateStyle()
            try applyFuzzy()
            try writePunctuation()
            showToast("设置已保存，点「应用并部署」生效")
        } catch {
            showToast("保存失败：\(error.localizedDescription)", error: true)
        }
    }

    /// 根据开关生成模糊音规则列表
    private func fuzzyRules() -> [String] {
        var rules: [String] = []
        if fuzzyZhCh {
            rules += [
                "    - derive/^([zcs])h/$1/",
                "    - derive/^([zcs])([^h])/$1h$2/"
            ]
        }
        if fuzzyNL {
            rules += ["    - derive/^l/n/", "    - derive/^n/l/"]
        }
        if fuzzyFH {
            rules += ["    - derive/^f/h/", "    - derive/^h/f/"]
        }
        if fuzzyGK {
            rules += ["    - derive/^g/k/", "    - derive/^k/g/"]
        }
        if fuzzyAngAn {
            rules += [
                "    - derive/ang$/an/", "    - derive/an$/ang/",
                "    - derive/eng$/en/", "    - derive/en$/eng/",
                "    - derive/ing$/in/", "    - derive/in$/ing/"
            ]
        }
        return rules
    }

    /// 模糊音：用 speller/algebra/+ 追加规则，不改动方案原有的 algebra 数组
    /// 这样即使雾凇拼音升级，规则依然叠加在最新的算法之上
    private func applyFuzzy() throws {
        let text = config.read(.schema)
        var lines = text.components(separatedBy: "\n")

        // 先移除本工具上次写入的区块
        let beginMark = "  # >>> RimeKit 模糊音 开始 <<<"
        let endMark = "  # >>> RimeKit 模糊音 结束 <<<"
        if let b = lines.firstIndex(of: beginMark), let e = lines.firstIndex(of: endMark), b < e {
            lines.removeSubrange(b...e)
        }

        let rules: [String] = fuzzyRules()

        // 一条都没开就只做清理
        if !rules.isEmpty {
            var block = [beginMark, "  speller/algebra/+:"]
            block += rules
            block.append(endMark)

            // 插到 patch: 段末尾
            var insertAt = lines.count
            if let patchIdx = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("patch:")
            }) {
                var i = patchIdx + 1
                insertAt = patchIdx + 1
                while i < lines.count {
                    let line = lines[i]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { i += 1; continue }
                    let indent = line.prefix(while: { $0 == " " }).count
                    if indent == 0 && !trimmed.hasPrefix("#") { break }
                    insertAt = i + 1
                    i += 1
                }
            } else {
                lines.append("patch:")
                insertAt = lines.count
            }
            lines.insert(contentsOf: block, at: insertAt)
        }

        let newText = lines.joined(separator: "\n")
        if newText != text {
            try config.write(newText, to: .schema)
        }
    }

    /// 读取模糊音当前状态
    func loadFuzzyState() {
        let text = config.read(.schema)
        fuzzyZhCh = text.contains("derive/^([zcs])h/$1/")
        fuzzyNL = text.contains("derive/^l/n/")
        fuzzyFH = text.contains("derive/^f/h/")
        fuzzyGK = text.contains("derive/^g/k/")
        fuzzyAngAn = text.contains("derive/ang$/an/")
    }

    /// 清空用户输入记忆（词频调频数据）
    /// 会删除 userdb，重启输入法后重建；不影响自定义短语
    func clearUserDict() {
        let fm = FileManager.default
        let userdb = RimeConfig.rimeDir.appendingPathComponent("rime_ice.userdb")

        guard fm.fileExists(atPath: userdb.path) else {
            showToast("没有找到用户词典", error: true)
            return
        }

        do {
            try fm.removeItem(at: userdb)
            showToast("已清空输入记忆，请重新部署")
        } catch {
            showToast("清空失败：\(error.localizedDescription)", error: true)
        }
    }

    /// 应用标点与输入行为设置
    ///
    /// 这些开关都在方案的 switches 数组里，用 reset 指定默认状态：
    ///   ascii_punct        1=英文标点  0=中文标点
    ///   traditionalization 1=繁体      0=简体
    ///   emoji              1=开启      0=关闭
    /// 用 @name 按名字定位，避免依赖数组下标（雾凇升级后顺序可能变）
    func applyPunctuation() {
        do {
            try writePunctuation()
            showToast("输入行为已保存，点「应用并部署」生效")
        } catch {
            showToast("保存失败：\(error.localizedDescription)", error: true)
        }
    }

    private func writePunctuation() throws {
        let text = config.read(.schema)
        var lines = text.components(separatedBy: "\n")

        let beginMark = "  # >>> RimeKit 输入行为 开始 <<<"
        let endMark = "  # >>> RimeKit 输入行为 结束 <<<"
        if let b = lines.firstIndex(of: beginMark),
           let e = lines.firstIndex(of: endMark), b < e {
            lines.removeSubrange(b...e)
        }

        var block = [beginMark]
        block.append("  \"switches/@ascii_punct/reset\": \(asciiPunct ? 1 : 0)")
        block.append("  \"switches/@traditionalization/reset\": \(traditionalDefault ? 1 : 0)")
        block.append("  \"switches/@emoji/reset\": \(emojiOn ? 1 : 0)")
        block.append(endMark)

        var insertAt = lines.count
        if let patchIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("patch:")
        }) {
            var i = patchIdx + 1
            insertAt = patchIdx + 1
            while i < lines.count {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { i += 1; continue }
                let indent = line.prefix(while: { $0 == " " }).count
                if indent == 0 && !trimmed.hasPrefix("#") { break }
                insertAt = i + 1
                i += 1
            }
        } else {
            lines.append("patch:")
            insertAt = lines.count
        }
        lines.insert(contentsOf: block, at: insertAt)

        try config.write(lines.joined(separator: "\n"), to: .schema)
    }

    func deploy() {
        config.deploy { ok, msg in
            self.showToast(msg, error: !ok)
        }
    }

    /// 恢复到初始配置（macOS 风格主题 + 候选 7 个 + 语法模型，无模糊音）
    /// 即引入界面工具之前手工调好的那套配置
    func resetToDefaults() {
        do {
            try config.write(DefaultProfile.squirrelCustom, to: .squirrel)
            try config.write(DefaultProfile.defaultCustom, to: .defaults)

            // 方案配置必须覆盖写，否则模糊音、标点等补丁块会残留
            // 语法模型不存在时去掉 grammar 段，避免部署报错
            let gramPath = RimeConfig.rimeDir
                .appendingPathComponent("wanxiang-lts-zh-hans.gram").path
            if FileManager.default.fileExists(atPath: gramPath) {
                try config.write(DefaultProfile.schemaCustom, to: .schema)
            } else {
                try config.write(DefaultProfile.schemaCustomNoGrammar, to: .schema)
            }

            loadFromDisk()
            showToast("已恢复默认配置，点「应用并部署」生效")
        } catch {
            showToast("恢复失败：\(error.localizedDescription)", error: true)
        }
    }

    func showToast(_ msg: String, error: Bool = false) {
        toast = msg
        toastIsError = error
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.toast == msg { self.toast = "" }
        }
    }
}
