import SwiftUI
import AppKit

/// 关于页：应用信息
struct AboutView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("关于")
                .font(.title)
                .fontWeight(.medium)

            brandSection
            infoSection
        }
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
