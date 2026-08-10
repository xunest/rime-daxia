import Foundation
import AppKit
import Carbon

/// 首次启动的引导安装
///
/// 分发形态是单个 .app，鼠须管引擎与雾凇配置以归档形式内嵌在
/// Contents/Resources/payload 下。安装分两半：
///
///   引擎 → /Library/Input Methods  需要 root，用 osascript 提权
///   配置 → ~/Library/Rime          当前用户就能写，无需提权
///
/// 提权只做「拷贝引擎 + 注册输入源」这一件事，配置铺设留在用户态，
/// 避免 root 建出属主为 root 的文件导致后续界面改配置失败。
enum Installer {

    /// 安装过程中的阶段，界面据此显示进度
    enum Stage: String {
        case idle = ""
        case copyingApp = "正在安装应用"
        case unpacking = "正在解压引擎"
        case installingEngine = "正在安装输入法引擎"
        case installingConfig = "正在铺设词库与配置"
        case registering = "正在注册输入法"
        case deploying = "正在首次部署"
        case done = "安装完成"
    }

    enum InstallError: LocalizedError {
        case payloadMissing(String)
        case unpackFailed(String)
        case privilegedFailed(String)
        case configFailed(String)
        case uninstallFailed(String)

        var errorDescription: String? {
            switch self {
            case .payloadMissing(let n):
                return "安装包不完整，缺少 \(n)。请重新下载完整的应用。"
            case .unpackFailed(let m):
                return "解压失败：\(m)"
            case .privilegedFailed(let m):
                return m
            case .configFailed(let m):
                return "铺设配置失败：\(m)"
            case .uninstallFailed(let m):
                return "卸载失败：\(m)"
            }
        }
    }

    /// 卸载范围
    enum UninstallScope {
        /// 只删设置工具，保留引擎、输入源与配置
        case settingsOnly
        /// 删设置工具 + 引擎，并注销输入源；配置可选
        case everything
    }

    // MARK: - 路径

    /// 内嵌载荷目录
    static var payloadDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("payload")
    }

    /// 引擎最终安装位置。文件名保持 Squirrel.app：
    /// Info.plist 的 InputMethodServerControllerClass 是
    /// Squirrel.SquirrelInputController，那个前缀是编译进二进制的
    /// Swift 模块名，改 bundle 名或 ID 会让 InputMethodKit 找不到控制器。
    static let engineDest = "/Library/Input Methods/Squirrel.app"

    /// 引擎的 bundle ID。写入输入源偏好时要用它，
    /// 不能改：Info.plist 的控制器类名带 Squirrel. 前缀。
    static let engineBundleID = "im.rime.inputmethod.Squirrel"

    /// 输入源 ID，注册与选中都用它
    ///
    /// 必须带 .Hans 后缀：不带后缀的 im.rime.inputmethod.Squirrel 只是
    /// 父级 bundle，TIS 属性里 IsSelectCapable 为 false，选它不会生效。
    /// 真正可切换的是 Hans（简体）与 Hant（繁体）两个输入模式。
    static let inputSourceID = "im.rime.inputmethod.Squirrel.Hans"

    // MARK: - 状态检测

    /// 引擎是否已安装
    static var engineInstalled: Bool {
        FileManager.default.fileExists(atPath: engineDest)
    }

    /// 配置目录是否已就绪。只看关键文件，光有空目录不算。
    static var configReady: Bool {
        let dir = RimeConfig.rimeDir
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("rime_ice.schema.yaml").path)
            && fm.fileExists(atPath: dir.appendingPathComponent("cn_dicts").path)
    }

    /// 是否带了内嵌载荷。从源码直接跑（开发时）没有 payload，
    /// 此时界面应提示去装官方鼠须管而不是显示引导安装。
    static var hasPayload: Bool {
        guard let dir = payloadDir else { return false }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("rime.tar.gz").path)
    }

    /// 全部就绪
    static var isFullyInstalled: Bool { engineInstalled && configReady }

    /// 当前是否从 DMG 或下载目录运行。
    /// 从 DMG 里直接跑时磁盘是只读的，配置写不进去，必须先搬到本地。
    static var runningFromTemporaryLocation: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/")
            || path.contains("/Downloads/")
            || path.contains("/AppTranslocation/")
    }

    /// 应用自身在「应用程序」里的目标位置
    static var appDestination: String {
        "/Applications/\(AppInfo.name).app"
    }

    /// 是否已在「应用程序」目录
    static var installedInApplications: Bool {
        Bundle.main.bundlePath == appDestination
    }

    // MARK: - 安装

    /// 执行安装。回调在主线程。
    /// - Parameters:
    ///   - branded: true 装品牌化引擎（菜单栏显示「大侠输入法」），
    ///              false 装官方原版。品牌版被系统拒绝加载时可回退。
    ///   - progress: 阶段变化
    ///   - completion: 成功与否及消息
    static func install(branded: Bool = true,
                        progress: @escaping (Stage) -> Void,
                        completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            func report(_ s: Stage) {
                DispatchQueue.main.async { progress(s) }
            }
            func finish(_ ok: Bool, _ msg: String) {
                DispatchQueue.main.async {
                    progress(ok ? .done : .idle)
                    completion(ok, msg)
                }
            }

            do {
                guard let payload = payloadDir else {
                    throw InstallError.payloadMissing("payload 目录")
                }

                let engineZip = payload.appendingPathComponent(
                    branded ? "DaxiaIME.zip" : "Squirrel.zip")
                let rimeTar = payload.appendingPathComponent("rime.tar.gz")

                for f in [engineZip, rimeTar] where
                    !FileManager.default.fileExists(atPath: f.path) {
                    throw InstallError.payloadMissing(f.lastPathComponent)
                }

                // 1. 解压引擎到临时目录
                report(.unpacking)
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("DaxiaIME-install-\(UUID().uuidString)")
                try FileManager.default.createDirectory(
                    at: tmp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tmp) }

                try run("/usr/bin/ditto", ["-x", "-k", engineZip.path, tmp.path],
                        wrap: { InstallError.unpackFailed($0) })

                // 归档里的目录名取决于打包时的 bundle 名
                let unpacked = tmp.appendingPathComponent(
                    branded ? "DaxiaIME.app" : "Squirrel.app")
                guard FileManager.default.fileExists(atPath: unpacked.path) else {
                    throw InstallError.unpackFailed("解压结果中找不到引擎")
                }

                // 2. 提权安装引擎并注册输入源；顺带把应用自身搬进「应用程序」
                report(.installingEngine)
                try installEnginePrivileged(from: unpacked)

                // 3. 铺设配置（用户态）
                report(.installingConfig)
                try installConfig(from: rimeTar)

                // 4. 首次部署：让新铺的词库先编译好，
                //    否则切过去可能因为还没构建而没有候选词
                report(.deploying)
                deployBlocking()

                // 5. 启用输入源并切换过去
                report(.registering)
                let enabled = registerInputSource()

                finish(true, enabled
                       ? "安装完成，已切换到大侠输入法，可以直接打字了"
                       : "安装完成。请到「系统设置 → 键盘 → 输入法」手动添加大侠输入法")
            } catch {
                finish(false, error.localizedDescription)
            }
        }
    }

    // MARK: - 引擎（需要 root）

    /// 用一次提权完成引擎拷贝与应用自身归位，避免让用户输多次密码
    ///
    /// 输入源的启用不放在这里：那是 root 会话，改不到登录用户的
    /// 输入源偏好，必须回到用户态进程用 TIS API 处理。
    private static func installEnginePrivileged(from src: URL) throws {
        var script = """
        set -e
        DEST='\(engineDest)'
        # 输入法进程由 launchd 托管，杀掉后会被立刻拉起。所以要
        # 先杀一次腾出文件，替换完再杀一次——第二次杀掉的是仍持有
        # 旧文件的进程，之后 launchd 会从新引擎重新启动它。
        # 少了第二次，状态栏会一直挂着旧版的图标和名字。
        #
        # 用 pkill 而不是 Squirrel --quit：后者对这类进程无效。
        /usr/bin/pkill -9 -x Squirrel 2>/dev/null || true
        sleep 1
        rm -rf "$DEST"
        /usr/bin/ditto '\(src.path)' "$DEST"
        # 再杀一次，清掉替换期间被 launchd 拉起的旧进程
        /usr/bin/pkill -9 -x Squirrel 2>/dev/null || true
        """

        // 还没在「应用程序」里就顺手搬过去，用户不必手动拖拽。
        // 从 DMG 运行时尤其必要：DMG 是只读卷，留在那里无法正常使用。
        if !installedInApplications {
            script += """

            APP_DEST='\(appDestination)'
            rm -rf "$APP_DEST"
            /usr/bin/ditto '\(Bundle.main.bundlePath)' "$APP_DEST"
            # 去掉隔离属性，避免下次打开被 Gatekeeper 拦
            /usr/bin/xattr -cr "$APP_DEST" 2>/dev/null || true
            """
        }

        try runPrivileged(script)
    }

    /// 通过 osascript 以管理员身份执行脚本，系统会弹出密码框
    private static func runPrivileged(_ shell: String) throws {
        // 脚本内的双引号与反斜杠要转义后嵌进 AppleScript 字符串
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", apple]

        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = Pipe()

        try proc.run()
        // 读取要在 waitUntilExit 之前，否则管道写满会死锁
        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            // 用户点取消时 osascript 返回 -128
            if msg.contains("-128") || msg.contains("User canceled") {
                throw InstallError.privilegedFailed("已取消授权，未做任何改动")
            }
            throw InstallError.privilegedFailed(
                "授权操作失败：" + msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - 配置（用户态）

    /// 铺设 ~/Library/Rime
    ///
    /// 对方可能已经在用鼠须管，直接覆盖会毁掉人家的词库与设置。
    /// 所以先解到临时目录，只把目标机器上缺的文件补进去，
    /// 已存在的一概不动。用户自己的 *.custom.yaml 与 userdb 天然保住。
    private static func installConfig(from tar: URL) throws {
        let fm = FileManager.default
        let dest = RimeConfig.rimeDir

        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DaxiaIME-rime-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try run("/usr/bin/tar", ["-xzf", tar.path, "-C", staging.path],
                wrap: { InstallError.configFailed($0) })

        if !fm.fileExists(atPath: dest.path) {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        }

        try mergeMissing(from: staging, to: dest)
        writeDefaultProfileIfAbsent()
    }

    /// 首次安装时写入预设配置（macOS 风格主题、候选 7 个、语法模型等）
    ///
    /// 只在文件不存在时写：对方可能已经在用鼠须管并调过自己的配置，
    /// 覆盖会毁掉人家的设置。这与 mergeMissing 的原则一致。
    private static func writeDefaultProfileIfAbsent() {
        let fm = FileManager.default
        let gram = RimeConfig.rimeDir
            .appendingPathComponent("wanxiang-lts-zh-hans.gram").path
        // 语法模型缺失时用不带 grammar 段的版本，否则部署会报错
        let schema = fm.fileExists(atPath: gram)
            ? DefaultProfile.schemaCustom
            : DefaultProfile.schemaCustomNoGrammar

        let config = RimeConfig()
        for (text, file) in [(DefaultProfile.squirrelCustom, RimeConfig.ConfigFile.squirrel),
                             (DefaultProfile.defaultCustom, .defaults),
                             (schema, .schema)] {
            guard !fm.fileExists(atPath: file.url.path) else { continue }
            try? config.write(text, to: file)
        }
    }

    /// 供自测调用：验证「只补缺失项」不会覆盖已有文件
    static func testMergeMissing(from src: URL, to dest: URL) {
        try? mergeMissing(from: src, to: dest)
    }

    /// 递归复制，只补目标端不存在的条目
    private static func mergeMissing(from src: URL, to dest: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: src.path)

        for name in items {
            let s = src.appendingPathComponent(name)
            let d = dest.appendingPathComponent(name)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: s.path, isDirectory: &isDir)

            if isDir.boolValue {
                if fm.fileExists(atPath: d.path) {
                    // 目录两边都有，继续往下比对，保住对方目录里的自有文件
                    try mergeMissing(from: s, to: d)
                } else {
                    try fm.copyItem(at: s, to: d)
                }
            } else if !fm.fileExists(atPath: d.path) {
                try fm.copyItem(at: s, to: d)
            }
        }
    }

    // MARK: - 输入源

    /// 注册并启用输入源，让它立刻出现在菜单栏可切换列表里
    ///
    /// 分两步，缺一不可：
    ///   1. Squirrel --install  向系统登记这个输入法（需要引擎已在位）
    ///   2. TISEnableInputSource + TISSelectInputSource  加入用户的
    ///      已启用列表并切换过去
    ///
    /// 第 2 步必须在当前这个用户态进程里调用。之前放在 osascript
    /// 提权子进程里执行，那是 root 会话，改不到登录用户的输入源偏好，
    /// 所以装完在菜单栏里看不到、也切不过去。
    @discardableResult
    static func registerInputSource() -> Bool {
        let bin = "\(engineDest)/Contents/MacOS/Squirrel"
        guard FileManager.default.isExecutableFile(atPath: bin) else { return false }

        // 先让系统识别这个输入法 bundle。刚拷进去时 LaunchServices
        // 可能还没扫到，注册一下能让 TIS 立即查得到。
        lsregister()

        runQuiet(bin, ["--install"])

        // 启动新引擎。安装时把旧进程杀干净了，这里要把新的拉起来，
        // 否则输入源虽已启用但没有进程响应按键。
        let app = NSWorkspace.shared
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        app.openApplication(at: URL(fileURLWithPath: engineDest),
                            configuration: cfg, completionHandler: nil)

        // 写偏好可以在任意线程做。菜单栏读的就是这个数组，
        // 写进去就已经能在列表里看到了。
        enableInPreferences()
        notifyInputSourceChanged()

        // 再把当前输入法切过去。TIS 系列函数必须在主线程调用：
        // HIToolbox 内部有 dispatch_assert_queue 断言，在后台队列上
        // 调用会直接 SIGTRAP 崩溃，而不是返回错误码。
        // 用 asyncAfter 递归重试而不是 sleep，避免卡住界面。
        DispatchQueue.main.async { selectInputSource(retriesLeft: 10) }

        return inputSourceEnabled
    }

    /// 在主线程把输入源切为当前输入法，查不到就稍后再试
    ///
    /// 引擎刚拷进去时 LaunchServices 可能还没扫到，TIS 查不到这个
    /// 输入源，所以要给几次机会。
    private static func selectInputSource(retriesLeft: Int) {
        if let src = findInputSource(inputSourceID) {
            TISEnableInputSource(src)
            TISSelectInputSource(src)
            return
        }
        guard retriesLeft > 0 else { return }
        if retriesLeft == 7 { lsregister() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            selectInputSource(retriesLeft: retriesLeft - 1)
        }
    }

    /// 把输入源写进「已启用」偏好数组
    ///
    /// 条目结构与手动在系统设置里添加时系统写入的完全一致：
    ///   Bundle ID / Input Mode / InputSourceKind
    private static func enableInPreferences() {
        let domain = "com.apple.HIToolbox" as CFString
        let key = "AppleEnabledInputSources" as CFString

        var list = (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
        // 已在列表里就不重复添加，避免菜单栏出现两项
        guard !list.contains(where: {
            ($0["Input Mode"] as? String) == inputSourceID
        }) else { return }

        list.append([
            "Bundle ID": engineBundleID,
            "Input Mode": inputSourceID,
            "InputSourceKind": "Input Mode"
        ])
        CFPreferencesSetAppValue(key, list as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    /// 告诉系统输入源列表变了，菜单栏据此立即重建
    private static func notifyInputSourceChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleEnabledInputSourcesChangedNotification"),
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// 输入源是否真的在「已启用」列表里
    ///
    /// 不查 TIS 的 IsEnabled 属性：那个属性会在实际未启用时也返回 true，
    /// 只有偏好数组才与菜单栏显示一致。
    static var inputSourceEnabled: Bool {
        let list = (CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString,
            "com.apple.HIToolbox" as CFString) as? [[String: Any]]) ?? []
        return list.contains { ($0["Input Mode"] as? String) == inputSourceID }
    }

    /// 按 ID 精确查找输入源
    ///
    /// includeAllInstalled 传 true 才能拿到尚未启用的输入源；
    /// 传 false 只返回已启用的，首次安装时查不到。
    private static func findInputSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        for includeAll in [true, false] {
            if let list = TISCreateInputSourceList(filter, includeAll)?
                .takeRetainedValue() as? [TISInputSource], let first = list.first {
                return first
            }
        }
        return nil
    }

    /// 让 LaunchServices 重新扫描输入法 bundle
    private static func lsregister() {
        let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks"
            + "/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        runQuiet(tool, ["-f", engineDest])
    }

    /// 跑一条命令并忽略输出与错误
    private static func runQuiet(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    /// 同步部署一次，让新铺的配置立即编译生效
    private static func deployBlocking() {
        let bin = "\(engineDest)/Contents/MacOS/Squirrel"
        guard FileManager.default.isExecutableFile(atPath: bin) else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["--reload"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - 卸载

    /// 执行卸载。回调在主线程。
    ///
    /// - settingsOnly：优先用户态删除设置工具，不弹密码；
    ///   若安装时由管理员写入导致无权删除，再提权只删设置工具。
    /// - everything：提权一次删引擎与设置工具，用户态注销输入源，
    ///   `removeConfig == true` 时再删 `~/Library/Rime`。
    /// 成功后会退出应用。
    static func uninstall(scope: UninstallScope,
                          removeConfig: Bool = false,
                          completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                switch scope {
                case .settingsOnly:
                    try uninstallSettingsOnly()
                case .everything:
                    try uninstallEverything(removeConfig: removeConfig)
                }
                DispatchQueue.main.async {
                    completion(true, "已卸载")
                    // 稍后再退，让界面先吃到成功回调
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.terminate(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    /// 仅卸载设置工具
    private static func uninstallSettingsOnly() throws {
        let paths = settingsAppPathsToRemove()
        guard !paths.isEmpty else {
            throw InstallError.uninstallFailed("未找到可卸载的设置工具")
        }

        let fm = FileManager.default
        var needPrivilege: [String] = []

        for path in paths {
            do {
                try fm.removeItem(atPath: path)
            } catch {
                needPrivilege.append(path)
            }
        }

        // 安装时经管理员 ditto 写入的副本属主是 root，用户态删不掉
        if !needPrivilege.isEmpty {
            let quoted = needPrivilege.map { "'\($0)'" }.joined(separator: " ")
            try runPrivileged("""
                set -e
                for p in \(quoted); do
                  rm -rf "$p"
                done
                """)
        }
    }

    /// 卸载全部：引擎 + 设置工具 + 注销输入源，可选清配置
    private static func uninstallEverything(removeConfig: Bool) throws {
        // 先在用户态关掉输入源，提权会话改不到登录用户的偏好
        disableInputSource()

        var script = """
        set -e
        /usr/bin/pkill -9 -x Squirrel 2>/dev/null || true
        sleep 1
        rm -rf '\(engineDest)'
        /usr/bin/pkill -9 -x Squirrel 2>/dev/null || true
        """

        for path in settingsAppPathsToRemove() {
            script += "\nrm -rf '\(path)'"
        }

        try runPrivileged(script)

        if removeConfig {
            let dir = RimeConfig.rimeDir
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
        }
    }

    /// 需要删除的设置工具路径（Applications 副本 + 当前正在跑的 .app）
    private static func settingsAppPathsToRemove() -> [String] {
        let fm = FileManager.default
        var paths: [String] = []
        var seen = Set<String>()

        func add(_ path: String) {
            guard !seen.contains(path), fm.fileExists(atPath: path) else { return }
            seen.insert(path)
            paths.append(path)
        }

        add(appDestination)

        let current = Bundle.main.bundlePath
        if current.hasSuffix(".app"),
           Bundle.main.bundleIdentifier == AppInfo.bundleID {
            add(current)
        }
        return paths
    }

    /// 从已启用列表移除输入源，并尽量禁用 TIS 源
    private static func disableInputSource() {
        let domain = "com.apple.HIToolbox" as CFString
        let key = "AppleEnabledInputSources" as CFString

        if var list = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] {
            let before = list.count
            list.removeAll { ($0["Input Mode"] as? String) == inputSourceID }
            if list.count != before {
                CFPreferencesSetAppValue(key, list as CFArray, domain)
                CFPreferencesAppSynchronize(domain)
            }
        }

        if let src = findInputSource(inputSourceID) {
            TISDisableInputSource(src)
        }
        notifyInputSourceChanged()
    }

    // MARK: - 工具

    /// 跑一条命令，失败时抛出带 stderr 的错误
    private static func run(_ path: String, _ args: [String],
                            wrap: (String) -> Error) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args

        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = Pipe()

        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            throw wrap(String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知错误")
        }
    }
}
