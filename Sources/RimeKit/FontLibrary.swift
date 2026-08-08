import AppKit

/// 中文字体分类：黑体、楷体、宋体、行书等，方便按风格挑选
enum FontCategory: String, CaseIterable, Identifiable {
    case sans = "黑体"
    case serif = "宋体"
    case kai = "楷体"
    case script = "行书草书"
    case rounded = "圆体"
    case other = "其他"

    var id: String { rawValue }
}

/// 一个可选字体
struct FontChoice: Identifiable, Hashable {
    let family: String          // Rime 里写入的字体家族名
    let category: FontCategory

    var id: String { family }
}

/// 系统字体枚举：只列出能显示中文的字体家族，并按字形归类
enum FontLibrary {

    /// 空字符串代表跟随皮肤/系统默认
    static let systemDefault = ""

    /// 所有可用中文字体，已归类
    static let choices: [FontChoice] = {
        // 用几个常用汉字探测字体是否真的覆盖中文
        let probes: [Unicode.Scalar] = ["好", "拼", "音"]

        let families = NSFontManager.shared.availableFontFamilies.filter { name in
            guard let font = NSFont(name: name, size: 12) else { return false }
            let charset = CTFontCopyCharacterSet(font as CTFont) as CharacterSet
            return probes.allSatisfy { charset.contains($0) }
        }

        let classified = families.map { FontChoice(family: $0, category: categorize($0)) }

        // 每类内部把常用字体排前面，其余按名称排序
        return FontCategory.allCases.flatMap { cat in
            let inCat = classified.filter { $0.category == cat }
            let head = preferred.filter { p in inCat.contains { $0.family == p } }
                .map { FontChoice(family: $0, category: cat) }
            let tail = inCat.filter { !preferred.contains($0.family) }
                .sorted { $0.family < $1.family }
            return head + tail
        }
    }()

    /// 兼容旧调用：扁平的字体名列表
    static var chineseFamilies: [String] { choices.map(\.family) }

    /// 各分类下的字体，空分类会被过滤掉
    static var grouped: [(FontCategory, [FontChoice])] {
        FontCategory.allCases.compactMap { cat in
            let items = choices.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    /// 常用字体，在各自分类里置顶
    private static let preferred = [
        "PingFang SC", "Hiragino Sans GB", "Heiti SC", "STHeiti",
        "Songti SC", "STSong", "Kaiti SC", "STKaiti",
        "Yuanti SC", "Xingkai SC", "Weibei SC",
    ]

    /// 按字体名里的风格关键字归类
    /// macOS 中文字体命名有规律，用关键字匹配足够可靠
    private static func categorize(_ name: String) -> FontCategory {
        let n = name.lowercased()

        // 行书、草书、手写风格
        if n.contains("xingkai") || n.contains("hannotate")
            || n.contains("hanzipen") || n.contains("baoli")
            || n.contains("wawati") || n.contains("weibei")
            || n.contains("lingwai") || n.contains("libian")
            || n.contains("klee") {
            return .script
        }
        // 圆体
        if n.contains("yuanti") || n.contains("yuppy")
            || n.contains("maru gothic") {
            return .rounded
        }
        // 楷体
        if n.contains("kaiti") || n.contains("kai")
            || n.contains("biaukai") {
            return .kai
        }
        // 宋体/明体，衬线
        if n.contains("songti") || n.contains("song")
            || n.contains("mincho") || n.contains("lisong")
            || n.contains("simsong") || n.contains("fangsong")
            || n.contains("lisung") || n.contains("bunkyu mincho") {
            return .serif
        }
        // 黑体/哥特，无衬线
        if n.contains("pingfang") || n.contains("heiti")
            || n.contains("hei") || n.contains("gothic")
            || n.contains("hiragino sans") || n.contains("yahei")
            || n.contains("lantinghei") || n.contains("ligothic")
            || n.contains("toppan bunkyu gothic") {
            return .sans
        }
        return .other
    }
}
