import Foundation

/// 一套皮肤的颜色定义，用于界面预览
struct Theme: Identifiable, Hashable {
    let id: String          // color_scheme ID，如 red_dark
    let name: String        // 显示名，如 夏日红-深色
    let author: String
    var backColor: String?
    var candidateTextColor: String?
    var hilitedCandidateBackColor: String?
    var hilitedCandidateTextColor: String?
    var labelColor: String?
    var commentTextColor: String?
    var borderColor: String?
    var fontPoint: Int?
    var cornerRadius: Int?
    var isLinear: Bool

    /// 粗略判断深浅色，用于预览区背板
    var isDark: Bool {
        guard let back = backColor,
              let rgb = RimeColor.parse(back) else { return false }
        // Rime 是 BGR 顺序，但亮度判断不受通道顺序影响
        let luma = 0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2
        return luma < 0.5
    }
}

/// Rime 颜色工具
/// 注意：Rime 的 0xBBGGRR 是 BGR 顺序，不是常见的 RGB
enum RimeColor {
    /// 解析 0xRRGGBB 形式（Rime 实为 BGR），返回 (r, g, b) 0~1
    static func parse(_ raw: String) -> (Double, Double, Double)? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingOccurrences(of: "\"", with: "")

        // 带 0x 前缀，明确是十六进制
        if s.lowercased().hasPrefix("0x") {
            let hex = String(s.dropFirst(2))
            guard hex.count == 3 || hex.count == 6 || hex.count == 8,
                  let v = UInt32(hex, radix: 16) else { return nil }
            // 8 位为 AABBGGRR，取低 24 位
            return fromBGR(hex.count == 8 ? (v & 0x00FFFFFF) : v)
        }

        // 无前缀且只含数字，视为十进制（SCT 会写成十进制）
        if s.allSatisfy(\.isNumber), let dec = UInt32(s) {
            return fromBGR(dec & 0x00FFFFFF)
        }

        // 无前缀但含字母，按十六进制尝试
        if let v = UInt32(s, radix: 16) {
            return fromBGR(s.count == 8 ? (v & 0x00FFFFFF) : v)
        }
        return nil
    }

    private static func fromBGR(_ v: UInt32) -> (Double, Double, Double) {
        let b = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let r = Double(v & 0xFF) / 255.0
        return (r, g, b)
    }
}

/// 从 themes.yaml 里解析所有 preset_color_schemes
struct ThemeLibrary {
    let themes: [Theme]

    /// 每套皮肤的完整 YAML 文本块，写入用户配置时原样复制
    let rawBlocks: [String: String]

    init(yamlContent: String) {
        var parsed: [Theme] = []
        var blocks: [String: String] = [:]

        let lines = yamlContent.components(separatedBy: "\n")

        // 定位 preset_color_schemes: 段
        var startIdx: Int?
        var baseIndent = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("preset_color_schemes:") {
                startIdx = i + 1
                baseIndent = line.prefix(while: { $0 == " " }).count
                break
            }
        }
        guard let start = startIdx else {
            self.themes = []
            self.rawBlocks = [:]
            return
        }

        // 逐个皮肤块切分：缩进比 preset_color_schemes 深一级且以 key: 结尾
        var currentID: String?
        var currentBlock: [String] = []
        var currentFields: [String: String] = [:]

        func flush() {
            guard let id = currentID else { return }
            let theme = Theme(
                id: id,
                name: currentFields["name"] ?? id,
                author: currentFields["author"] ?? "",
                backColor: currentFields["back_color"],
                candidateTextColor: currentFields["candidate_text_color"],
                hilitedCandidateBackColor: currentFields["hilited_candidate_back_color"],
                hilitedCandidateTextColor: currentFields["hilited_candidate_text_color"],
                labelColor: currentFields["label_color"],
                commentTextColor: currentFields["comment_text_color"],
                borderColor: currentFields["border_color"],
                fontPoint: currentFields["font_point"].flatMap { Int($0) },
                cornerRadius: currentFields["corner_radius"].flatMap { Int($0) },
                isLinear: (currentFields["candidate_list_layout"] == "linear")
                    || (currentFields["horizontal"] == "true")
            )
            parsed.append(theme)
            blocks[id] = currentBlock.joined(separator: "\n")
            currentID = nil
            currentBlock = []
            currentFields = [:]
        }

        var i = start
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if currentID != nil { currentBlock.append(line) }
                i += 1
                continue
            }

            let indent = line.prefix(while: { $0 == " " }).count

            // 离开 preset_color_schemes 段
            if indent <= baseIndent && !trimmed.hasPrefix("#") {
                break
            }

            // 新皮肤块的起始：`  xxx:` 且冒号后无值
            if indent == baseIndent + 2,
               trimmed.hasSuffix(":"),
               !trimmed.hasPrefix("#") {
                flush()
                currentID = String(trimmed.dropLast())
                currentBlock = [line]
                i += 1
                continue
            }

            // 皮肤块内的字段
            if currentID != nil {
                currentBlock.append(line)
                if !trimmed.hasPrefix("#"),
                   let colon = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                    if let val = YAMLLineEditor.extractValue(from: trimmed) {
                        currentFields[key] = val
                    }
                }
            }
            i += 1
        }
        flush()

        self.themes = parsed
        self.rawBlocks = blocks
    }
}
