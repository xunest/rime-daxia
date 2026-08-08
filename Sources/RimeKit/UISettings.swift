import Foundation
import AppKit

/// 应用固定信息
enum AppInfo {
    static let name = "大侠输入法"
    static let bundleID = "com.daxia.ime.kit"

    /// 版本号，改版本只需改 Info.plist 一处
    ///
    /// 从源码直接跑（没有 app bundle）时读不到，退回 "dev" 以便区分。
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
    }

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
