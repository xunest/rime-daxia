import SwiftUI

/// 一条自定义短语
struct Phrase: Identifiable, Equatable {
    let id = UUID()
    var text: String      // 词汇，如 大侠
    var code: String      // 编码，如 dx
    var weight: String    // 权重，可空
}

/// 常用语页：编辑 custom_phrase.txt
/// 对标微信输入法的「常用语」，这里的词永远排在候选第一位
struct PhraseView: View {
    @EnvironmentObject var store: AppStore

    @State private var phrases: [Phrase] = []
    @State private var header: String = ""      // 文件头部注释，原样保留
    @State private var newText = ""
    @State private var newCode = ""
    @State private var loaded = false
    @State private var search = ""

    private var filtered: [Phrase] {
        guard !search.isEmpty else { return phrases }
        return phrases.filter {
            $0.text.localizedCaseInsensitiveContains(search)
                || $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            addBar
            Divider()
            list
            Divider()
            footer
        }
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用语")
                .font(.headline)
            Text("在这里添加人名、邮箱、常用短句。输入编码即可置顶上屏，不受使用频率影响。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("词汇，如 大侠", text: $newText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Image(systemName: "arrow.left")
                    .foregroundStyle(.secondary)
                TextField("编码，如 dx", text: $newCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                Button("添加") { add() }
                    .disabled(newText.isEmpty || newCode.isEmpty)
                Spacer()
            }
        }
        .padding(20)
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已有 \(phrases.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if phrases.isEmpty {
                Spacer()
                Text("还没有常用语")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { phrase in
                            HStack {
                                Text(phrase.text)
                                    .frame(width: 180, alignment: .leading)
                                    .lineLimit(1)
                                Text(phrase.code)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                if !phrase.weight.isEmpty {
                                    Text("权重 \(phrase.weight)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button {
                                    remove(phrase)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("保存到 custom_phrase.txt")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("保存") { save() }
                .keyboardShortcut("s")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 数据

    /// 解析文件：注释区原样保留，只解析「此行之后不能写注释」之后的数据行
    private func load() {
        let content = store.config.read(.customPhrase)
        guard !content.isEmpty else { return }

        let lines = content.components(separatedBy: "\n")
        var headerLines: [String] = []
        var dataLines: [String] = []
        var inData = false

        for line in lines {
            if !inData {
                headerLines.append(line)
                // rime-ice 的约定标记
                if line.contains("此行之后不能写注释") {
                    inData = true
                }
                continue
            }
            dataLines.append(line)
        }

        // 若没有那行标记，退化为：注释和空行算头部，第一条数据行开始算数据
        if !inData {
            headerLines = []
            dataLines = lines
        }

        header = headerLines.joined(separator: "\n")
        phrases = dataLines.compactMap { line -> Phrase? in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return nil }
            let parts = line.components(separatedBy: "\t").filter { !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            return Phrase(
                text: parts[0],
                code: parts[1],
                weight: parts.count >= 3 ? parts[2] : ""
            )
        }
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        let code = newCode.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !code.isEmpty else { return }

        if phrases.contains(where: { $0.text == text && $0.code == code }) {
            store.showToast("这条已存在", error: true)
            return
        }
        phrases.append(Phrase(text: text, code: code, weight: ""))
        newText = ""
        newCode = ""
    }

    private func remove(_ phrase: Phrase) {
        phrases.removeAll { $0.id == phrase.id }
    }

    private func save() {
        var out = header.isEmpty ? "" : header + "\n"
        for p in phrases {
            if p.weight.isEmpty {
                out += "\(p.text)\t\(p.code)\n"
            } else {
                out += "\(p.text)\t\(p.code)\t\(p.weight)\n"
            }
        }
        do {
            try store.config.write(out, to: .customPhrase)
            store.showToast("已保存 \(phrases.count) 条常用语，点「应用并部署」生效")
        } catch {
            store.showToast("保存失败：\(error.localizedDescription)", error: true)
        }
    }
}
