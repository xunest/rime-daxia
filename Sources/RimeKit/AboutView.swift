import SwiftUI
import AppKit

/// 关于页：应用信息与卸载
struct AboutView: View {
    @EnvironmentObject var store: AppStore

    @State private var scope: Installer.UninstallScope = .settingsOnly
    @State private var removeConfig = false
    @State private var showConfirm = false
    @State private var uninstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("关于")
                .font(.title)
                .fontWeight(.medium)

            brandSection
            infoSection
            uninstallSection
        }
        .alert(confirmTitle, isPresented: $showConfirm) {
            Button("取消", role: .cancel) { }
            Button("卸载", role: .destructive) { performUninstall() }
        } message: {
            Text(confirmMessage)
        }
        .disabled(uninstalling)
    }

    // MARK: - 品牌
    private var brandSection: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppIcon.current(size: 256))
                .resizable()
                .frame(width: 76, height: 76)
                .cornerRadius(16)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(.system(size: 20, weight: .medium))
                Text("简单好用的拼音输入法")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("版本 \(AppInfo.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - 信息
    private var infoSection: some View {
        GroupBox(label: Text("信息").font(.headline)) {
            VStack(spacing: 0) {
                infoRow("配置目录", RimeConfig.rimeDir.path)
                Divider()
                infoRow("内置皮肤", "\(store.library.themes.count) 套")
                Divider()
                HStack {
                    Text("皮肤来源")
                        .font(.system(size: 13))
                    Spacer()
                    Link("allensu_squirrel_theme",
                         destination: URL(string: "https://github.com/jsonsuxing/allensu_squirrel_theme")!)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.wxGreen)
                    Text("所有配置保存在本地，不联网、不上传")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    // MARK: - 卸载
    private var uninstallSection: some View {
        GroupBox(label: Text("卸载").font(.headline)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("选择要移除的内容")
                    .font(.system(size: 13))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 10) {
                    scopeOption(
                        .settingsOnly,
                        title: "仅卸载设置工具",
                        detail: "删除本配置应用，保留输入法引擎与词库，仍可继续打字"
                    )
                    scopeOption(
                        .everything,
                        title: "卸载全部",
                        detail: "删除设置工具、输入法引擎，并注销输入源"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if scope == .everything {
                    Divider()
                    Toggle(isOn: $removeConfig) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("同时删除配置与词库")
                                .font(.system(size: 13))
                            Text("包含 \(RimeConfig.rimeDir.path)，词频与自定义短语也会被清除")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                HStack {
                    if uninstalling {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在卸载…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(scope == .settingsOnly
                             ? "通常无需输入密码"
                             : "需要输入管理员密码以删除引擎")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("卸载…") { showConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(uninstalling)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    private func scopeOption(_ value: Installer.UninstallScope,
                             title: String,
                             detail: String) -> some View {
        Button {
            scope = value
            if value == .settingsOnly { removeConfig = false }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: scope == value
                      ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(scope == value ? Color.wxGreen : .secondary)
                    .font(.system(size: 16))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.wxText)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var confirmTitle: String {
        scope == .settingsOnly ? "卸载设置工具？" : "卸载全部？"
    }

    private var confirmMessage: String {
        switch scope {
        case .settingsOnly:
            return "将删除本配置应用。输入法引擎与词库会保留，仍可继续使用大侠输入法打字。"
        case .everything:
            if removeConfig {
                return "将删除设置工具、输入法引擎、输入源，以及本地配置与词库。此操作不可恢复。"
            }
            return "将删除设置工具与输入法引擎，并注销输入源。配置目录默认保留，之后仍可手动清理。"
        }
    }

    private func performUninstall() {
        uninstalling = true
        Installer.uninstall(scope: scope, removeConfig: removeConfig) { ok, msg in
            uninstalling = false
            if !ok {
                store.showToast(msg, error: true)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
