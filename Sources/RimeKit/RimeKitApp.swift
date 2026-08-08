import SwiftUI
import AppKit

@main
struct RimeKitApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let args = CommandLine.arguments

        if args.contains("--selftest") {
            exit(SelfTest.run())
        }

        // 供 build.sh 生成 .icns 用
        if let idx = args.firstIndex(of: "--export-icons"), idx + 1 < args.count {
            let dir = URL(fileURLWithPath: args[idx + 1])
            do {
                try AppIcon.exportIconSet(to: dir)
                exit(0)
            } catch {
                FileHandle.standardError.write(
                    "导出图标失败: \(error.localizedDescription)\n".data(using: .utf8)!)
                exit(1)
            }
        }

        // 供 make_payload.sh 生成输入法菜单栏图标（必须是矢量 PDF）
        if let idx = args.firstIndex(of: "--export-menubar-pdf"), idx + 1 < args.count {
            let url = URL(fileURLWithPath: args[idx + 1])
            do {
                try AppIcon.exportMenuBarPDF(to: url)
                exit(0)
            } catch {
                FileHandle.standardError.write(
                    "导出菜单栏图标失败: \(error.localizedDescription)\n".data(using: .utf8)!)
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            RootView()
                .environmentObject(store)
        }
        // 用 contentSize 让窗口贴合内容：安装页是固定尺寸的紧凑窗口，
        // 主界面自己声明了 minWidth/minHeight，仍可自由放大。
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// 启动后应用图标，并在菜单栏常驻一个入口
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeIcon.apply()
        setupStatusItem()
    }

    /// 菜单栏图标：鼠须管的菜单无法注入第三方项，所以自建一个入口
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "keyboard.badge.gearshape",
            accessibilityDescription: AppInfo.name
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "打开\(AppInfo.name)",
                     action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新部署输入法",
                     action: #selector(deployRime), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for mi in menu.items where mi.action == #selector(openWindow)
            || mi.action == #selector(deployRime) {
            mi.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.contentViewController != nil }) {
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func deployRime() {
        RimeConfig().deploy { _, _ in }
    }

    /// 点关闭按钮后保留进程，从菜单栏还能再打开
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
