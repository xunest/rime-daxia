import SwiftUI

/// 自定义配色：只暴露真正影响观感的 5 个颜色
///
/// Rime 的颜色字段不能直接写在 style 下，必须挂在某套 preset_color_schemes 里。
/// 所以自定义配色实际是生成 daxia_custom / daxia_custom_dark 两套方案。
struct CustomScheme: Equatable {
    var back: Color                 // 候选窗背景
    var candidateText: Color        // 未选中候选字
    var hilitedText: Color          // 选中候选字
    var hilitedBack: Color          // 选中候选背景
    var label: Color                // 序号与拼音

    /// 选中项不画底色，与候选窗背景一致，只靠文字颜色区分
    var plainHilite: Bool = false

    /// 实际写入的选中背景色
    var effectiveHilitedBack: Color { plainHilite ? back : hilitedBack }

    /// 浅色默认值，取自 macos_light
    static let defaultLight = CustomScheme(
        back: Color(red: 1, green: 1, blue: 1),
        candidateText: Color(red: 0.15, green: 0.15, blue: 0.15),
        hilitedText: Color(red: 1, green: 1, blue: 1),
        hilitedBack: Color(red: 0.0, green: 0.48, blue: 1.0),
        label: Color(red: 0.6, green: 0.6, blue: 0.6)
    )

    /// 深色默认值，取自 macos_dark
    static let defaultDark = CustomScheme(
        back: Color(red: 0.14, green: 0.14, blue: 0.14),
        candidateText: Color(red: 0.93, green: 0.93, blue: 0.93),
        hilitedText: Color(red: 1, green: 1, blue: 1),
        hilitedBack: Color(red: 0.0, green: 0.48, blue: 1.0),
        label: Color(red: 0.55, green: 0.55, blue: 0.55)
    )

    /// 浅色方案在 squirrel.custom.yaml 里的 ID
    static let lightID = "daxia_custom"
    static let darkID = "daxia_custom_dark"

    /// 从任意一套皮肤取色作为自定义起点
    init(from theme: Theme, fallback: CustomScheme) {
        back = Color(rime: theme.backColor) ?? fallback.back
        candidateText = Color(rime: theme.candidateTextColor) ?? fallback.candidateText
        hilitedText = Color(rime: theme.hilitedCandidateTextColor) ?? fallback.hilitedText
        hilitedBack = Color(rime: theme.hilitedCandidateBackColor) ?? fallback.hilitedBack
        label = Color(rime: theme.labelColor) ?? fallback.label

        // 选中背景与窗口背景相同，说明这套皮肤本来就是无底色风格
        if let hi = theme.hilitedCandidateBackColor.flatMap(RimeColor.parse),
           let bg = theme.backColor.flatMap(RimeColor.parse) {
            plainHilite = abs(hi.0 - bg.0) < 0.01
                && abs(hi.1 - bg.1) < 0.01
                && abs(hi.2 - bg.2) < 0.01
        } else {
            plainHilite = false
        }
    }

    init(back: Color, candidateText: Color, hilitedText: Color,
         hilitedBack: Color, label: Color, plainHilite: Bool = false) {
        self.back = back
        self.candidateText = candidateText
        self.hilitedText = hilitedText
        self.hilitedBack = hilitedBack
        self.label = label
        self.plainHilite = plainHilite
    }

    /// 生成可写入 YAML 的方案块，缩进 4 空格（与内置库一致）
    func yamlBlock(id: String, name: String) -> String {
        """
            \(id):
              name: "\(name)"
              author: 大侠输入法
              back_color: \(back.rimeHex)
              candidate_text_color: \(candidateText.rimeHex)
              hilited_candidate_text_color: \(hilitedText.rimeHex)
              hilited_candidate_back_color: \(effectiveHilitedBack.rimeHex)
              hilited_candidate_label_color: \(hilitedText.rimeHex)
              label_color: \(label.rimeHex)
              comment_text_color: \(label.rimeHex)
              text_color: \(label.rimeHex)
              hilited_text_color: \(candidateText.rimeHex)
              hilited_back_color: \(back.rimeHex)
              border_color: \(back.rimeHex)
        """
    }

    /// 供预览复用，转成 Theme
    func asTheme(id: String, name: String) -> Theme {
        Theme(
            id: id,
            name: name,
            author: "大侠输入法",
            backColor: back.rimeHex,
            candidateTextColor: candidateText.rimeHex,
            hilitedCandidateBackColor: effectiveHilitedBack.rimeHex,
            hilitedCandidateTextColor: hilitedText.rimeHex,
            labelColor: label.rimeHex,
            commentTextColor: label.rimeHex,
            borderColor: back.rimeHex,
            fontPoint: nil,
            cornerRadius: nil,
            isLinear: true
        )
    }
}
