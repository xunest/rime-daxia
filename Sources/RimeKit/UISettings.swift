import Foundation
import AppKit

/// 应用固定信息
enum AppInfo {
    static let name = "大侠输入法"
    static let bundleID = "com.daxia.ime.kit"
    static let version = "1.0"

    /// 最低系统版本，从 Info.plist 读，避免与实际打包设置不一致
    static var minSystem: String {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion")
            as? String ?? "13.0"
    }
}

/// 运行时应用图标：确保程序坞显示的是我们绘制的图标
enum RuntimeIcon {
    static func apply() {
        NSApp.applicationIconImage = AppIcon.current(size: 512)
    }
}
