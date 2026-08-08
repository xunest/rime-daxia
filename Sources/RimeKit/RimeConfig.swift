import Foundation

/// Rime 配置文件读写与部署
final class RimeConfig: ObservableObject {
    static let rimeDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Rime")

    static let squirrelApp = "/Library/Input Methods/Squirrel.app"

    enum ConfigFile: String {
        case squirrel = "squirrel.custom.yaml"
        case defaults = "default.custom.yaml"
        case schema = "rime_ice.custom.yaml"
        case customPhrase = "custom_phrase.txt"

        var url: URL { RimeConfig.rimeDir.appendingPathComponent(rawValue) }
    }

    @Published var lastMessage: String = ""
    @Published var isDeploying = false

    /// 鼠须管是否已安装
    var squirrelInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.squirrelApp)
    }

    var rimeDirExists: Bool {
        FileManager.default.fileExists(atPath: Self.rimeDir.path)
    }

    // MARK: - 读写

    func read(_ file: ConfigFile) -> String {
        (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
    }

    func write(_ content: String, to file: ConfigFile) throws {
        try content.write(to: file.url, atomically: true, encoding: .utf8)
    }

    // MARK: - 部署

    func deploy(completion: @escaping (Bool, String) -> Void) {
        guard squirrelInstalled else {
            completion(false, "未找到输入法引擎，请重新安装")
            return
        }

        isDeploying = true
        let bin = "\(Self.squirrelApp)/Contents/MacOS/Squirrel"

        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = ["--reload"]

            let pipe = Pipe()
            proc.standardError = pipe
            proc.standardOutput = pipe

            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    self.isDeploying = false
                    if proc.terminationStatus == 0 {
                        completion(true, "已重新部署，配置生效中")
                    } else {
                        completion(false, "部署失败：\(output)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDeploying = false
                    completion(false, "无法启动部署：\(error.localizedDescription)")
                }
            }
        }
    }
}
