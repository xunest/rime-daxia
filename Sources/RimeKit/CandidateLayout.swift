import Foundation

/// 候选窗排版模式
///
/// Rime 用两个独立字段描述排版，组合起来才是完整效果：
///   candidate_list_layout  linear 一行横排 / stacked 多行竖排
///   text_orientation       horizontal 文字水平 / vertical 文字旋转 90 度
enum CandidateLayout: String, CaseIterable, Identifiable {
    /// 候选横向排成一行，最常见
    case horizontal
    /// 候选纵向排成一列，每行一个词
    case vertical
    /// 候选纵向排列且文字旋转，竖排书写风格
    case verticalText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal:  return "横排"
        case .vertical:    return "竖排"
        case .verticalText: return "竖排竖文"
        }
    }

    var hint: String {
        switch self {
        case .horizontal:  return "候选词排成一行，从左到右"
        case .vertical:    return "候选词排成一列，每行一个"
        case .verticalText: return "候选词排成一列且文字旋转，仿古籍竖排"
        }
    }

    /// 对应 candidate_list_layout
    var listLayout: String {
        self == .horizontal ? "linear" : "stacked"
    }

    /// 对应 text_orientation
    var textOrientation: String {
        self == .verticalText ? "vertical" : "horizontal"
    }

    /// 预览时是否按一行横排渲染
    var isLinear: Bool { self == .horizontal }

    /// 从配置里的两个字段还原
    static func from(listLayout: String?, textOrientation: String?) -> CandidateLayout {
        let stacked = (listLayout == "stacked")
        let verticalText = (textOrientation == "vertical")
        if !stacked { return .horizontal }
        return verticalText ? .verticalText : .vertical
    }
}
