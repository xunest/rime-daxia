import SwiftUI
import AppKit

/// 首启引导安装页
///
/// 目标机器上没装引擎或没铺配置时显示。全部资源已内嵌在 app 里，
/// 点一次按钮、输一次密码就能装完，不需要用户自己去下载鼠须管。
struct SetupView: View {
    @EnvironmentObject var store: AppStore

    @State private var stage = Installer.Stage.idle
    @State private var installing = false
    @State private var errorMessage = ""
    /// 品牌版被系统拒绝加载时，允许改装官方原版
    @State private var showFallback = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: AppIcon.current(size: 256))
                .resizable()
                .frame(width: 96, height: 96)
                .cornerRadius(20)

            Text(AppInfo.name)
                .font(.system(size: 21, weight: .medium))
                .padding(.top, 18)

            Text(AppInfo.version)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 5)

            if installing {
                progressBlock
            } else if !errorMessage.isEmpty {
                errorBlock
            } else {
                readyBlock
            }

            Spacer()

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    // MARK: - 待安装

    /// 只留一个按钮
    ///
    /// 装到哪、动了什么，用户此刻并不关心，也没法据此做决定；
    /// 真正需要知道的是「不会覆盖已有数据」，放在按钮下方一行足够。
    private var readyBlock: some View {
        VStack(spacing: 14) {
            Button {
                startInstall(branded: true)
            } label: {
                Text("安装")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.wxGreen)
            .controlSize(.large)

            Text("适用于 macOS \(AppInfo.minSystem) 或更高版本")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 34)
    }

    // MARK: - 安装中

    private var progressBlock: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(stage.rawValue)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            // 词库有几百兆，铺设阶段耗时最久，先说明避免以为卡死
            if stage == .installingConfig {
                Text("词库较大，请耐心等待")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 36)
    }

    // MARK: - 失败

    private var errorBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button("重试") { startInstall(branded: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.wxGreen)

                // 品牌化引擎经过重签名，个别机器的安全策略可能拒绝加载，
                // 这时改装官方签名的原版，代价是菜单栏显示「鼠须管」
                if showFallback {
                    Button("改用官方原版引擎") { startInstall(branded: false) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, 30)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 6) {
            if !Installer.hasPayload {
                // 从源码直接运行时没有内嵌载荷，此时只能手工装
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("当前版本未内嵌安装资源，请手动安装鼠须管")
                    Link("前往官网", destination: URL(string: "https://rime.im/download/")!)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            // GPL-3.0 要求标明来源，不能省
            Text("基于 RIME 鼠须管与雾凇拼音，均为开源项目")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 动作

    private func startInstall(branded: Bool) {
        errorMessage = ""
        installing = true
        // 记录安装前的位置：若安装过程把应用搬进了「应用程序」，
        // 当前进程仍跑在旧位置（可能是只读的 DMG），需要重启到新位置
        let wasElsewhere = !Installer.installedInApplications

        Installer.install(branded: branded, progress: { s in
            stage = s
        }, completion: { ok, msg in
            installing = false
            if ok {
                store.refreshInstallState()
                store.loadFromDisk()
                store.showToast(msg)
                // 应用刚被搬进「应用程序」，当前进程还跑在旧位置
                // （可能是只读的 DMG 卷），换到新副本继续运行。
                // 输入法本身此时已经装好并启用，重启只影响这个配置界面。
                if wasElsewhere {
                    relaunchFromApplications()
                }
            } else {
                errorMessage = msg
                // 引擎装上了却仍不可用，才提供回退原版的选项
                showFallback = branded && Installer.engineInstalled
            }
        })
    }

    /// 从「应用程序」里的新副本重启，然后退出当前进程
    private func relaunchFromApplications() {
        let dest = URL(fileURLWithPath: Installer.appDestination)
        guard FileManager.default.fileExists(atPath: dest.path) else { return }

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        // 稍等一下再切换，让用户看到「安装完成」的提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSWorkspace.shared.openApplication(at: dest, configuration: cfg) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}
