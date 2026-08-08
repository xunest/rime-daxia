import Foundation

/// 行级 YAML 编辑器
///
/// 设计目标：只替换目标 key 所在的那一行，其余字节原样保留。
/// 这样注释、缩进风格、空行、十六进制颜色写法都不会被破坏。
/// 不做 YAML 解析再序列化（那正是 SCT 丢注释的原因）。
struct YAMLLineEditor {
    private(set) var lines: [String]

    init(content: String) {
        // 保留原始行结构，不合并空行
        self.lines = content.components(separatedBy: "\n")
    }

    var content: String {
        lines.joined(separator: "\n")
    }

    /// 查找 patch 段内某个键的行号
    /// 支持两种写法：扁平路径 `style/color_scheme: x` 和嵌套 `style:` + 缩进 `color_scheme: x`
    private func findFlat(_ path: String) -> Int? {
        let pattern = "^\\s*\"?\(NSRegularExpression.escapedPattern(for: path))\"?\\s*:"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        for (i, line) in lines.enumerated() {
            if isComment(line) { continue }
            let range = NSRange(line.startIndex..., in: line)
            if re.firstMatch(in: line, range: range) != nil { return i }
        }
        return nil
    }

    /// 查找嵌套写法：父键下的子键
    private func findNested(parent: String, child: String) -> Int? {
        guard let parentLine = findFlat(parent) else { return nil }
        let parentIndent = indentWidth(lines[parentLine])

        var i = parentLine + 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty || isComment(line) {
                i += 1
                continue
            }
            let indent = indentWidth(line)
            // 缩进回到父级或更浅，说明已离开该块
            if indent <= parentIndent { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(child):") || trimmed.hasPrefix("\"\(child)\":") {
                return i
            }
            i += 1
        }
        return nil
    }

    private func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private func indentWidth(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    /// 读取值（去掉行尾注释和引号）
    func value(forPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        var lineIndex: Int?

        if let i = findFlat(path) {
            lineIndex = i
        } else if parts.count == 2, let i = findNested(parent: parts[0], child: parts[1]) {
            lineIndex = i
        }

        guard let idx = lineIndex else { return nil }
        return Self.extractValue(from: lines[idx])
    }

    static func extractValue(from line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var raw = String(line[line.index(after: colon)...])

        // 去掉行尾注释：只在 # 前有空白时才算注释，避免误伤 #RRGGBB 之类
        if let hashRange = raw.range(of: "\\s+#", options: .regularExpression) {
            raw = String(raw[..<hashRange.lowerBound])
        }
        raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            raw = String(raw.dropFirst().dropLast())
        } else if raw.hasPrefix("'") && raw.hasSuffix("'") && raw.count >= 2 {
            raw = String(raw.dropFirst().dropLast())
        }
        return raw.isEmpty ? nil : raw
    }

    /// 就地替换值，保留原缩进、原 key 写法、原行尾注释
    /// 若 key 不存在则追加到 patch: 段末尾
    mutating func setValue(_ newValue: String, forPath path: String) {
        let parts = path.split(separator: "/").map(String.init)
        var lineIndex: Int?

        if let i = findFlat(path) {
            lineIndex = i
        } else if parts.count == 2, let i = findNested(parent: parts[0], child: parts[1]) {
            lineIndex = i
        }

        if let idx = lineIndex {
            lines[idx] = Self.replaceValue(in: lines[idx], with: newValue)
        } else {
            insertIntoPatch(path: path, value: newValue)
        }
    }

    static func replaceValue(in line: String, with newValue: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        let keyPart = String(line[...colon])
        let after = String(line[line.index(after: colon)...])

        // 提取并保留行尾注释
        var trailingComment = ""
        if let hashRange = after.range(of: "\\s+#", options: .regularExpression) {
            trailingComment = String(after[hashRange.lowerBound...])
        }

        return "\(keyPart) \(newValue)\(trailingComment)"
    }

    /// 在 patch: 段末尾插入新键（扁平路径写法）
    private mutating func insertIntoPatch(path: String, value: String) {
        guard let patchLine = findFlat("patch") else {
            // 没有 patch 段，整体补一个
            lines.append("patch:")
            lines.append("  \(path): \(value)")
            return
        }

        // 找到 patch 块的末尾（最后一个缩进 > 0 的非空行）
        var insertAt = patchLine + 1
        var i = patchLine + 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            if indentWidth(line) == 0 && !isComment(line) { break }
            insertAt = i + 1
            i += 1
        }
        lines.insert("  \(path): \(value)", at: insertAt)
    }
}
