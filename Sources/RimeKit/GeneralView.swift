import SwiftUI

/// 输入设置页：候选窗、模糊音、标点、词库
/// 这些设置与皮肤无关，换皮肤不会影响
struct GeneralView: View {
    @EnvironmentObject var store: AppStore
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("输入设置")
                .font(.title)
                .fontWeight(.medium)

            candidateSection
            fuzzySection
            punctSection
            dictSection
        }
        .alert("清空输入记忆？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) { store.clearUserDict() }
        } message: {
            Text("会删除累积的词频调频数据，候选词顺序回到初始状态。自定义短语不受影响。")
        }
    }

    // MARK: - 候选窗
    private var candidateSection: some View {
        GroupBox(label: Text("候选窗").font(.headline)) {
            VStack(spacing: 0) {
                SettingRow("候选词数量") {
                    numberRow($store.pageSize, range: 3...9, step: 1, unit: "")
                }
                Divider()

                SettingRow("候选词字号") {
                    numberRow($store.fontSize, range: 12...32, unit: "")
                }
                Divider()

                SettingRow("候选词字体", hint: "按字形分类，每项以该字体显示样张") {
                    Picker("", selection: $store.fontFace) {
                        Text("跟随皮肤").tag("")
                        ForEach(FontLibrary.grouped, id: \.0) { cat, items in
                            Section(cat.rawValue) {
                                ForEach(items) { item in
                                    // 用该字体本身渲染，下拉时即可看出差别
                                    Text("\(item.family)　你好拼音")
                                        .font(.custom(item.family, size: 13))
                                        .tag(item.family)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                Divider()

                SettingRow("序号字号") {
                    numberRow($store.labelFontSize, range: 8...24, unit: "")
                }
                Divider()

                SettingRow("排列方向", hint: store.layout.hint) {
                    Picker("", selection: $store.layout) {
                        ForEach(CandidateLayout.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                Divider()

                SettingRow("不透明度", hint: "低于 100 时启用毛玻璃背景") {
                    numberRow($store.opacity, range: 30...100, step: 5, unit: "%")
                }
                Divider()

                SettingRow("圆角大小", hint: "候选窗外框圆角") {
                    numberRow($store.cornerRadius, range: 0...20, step: 1, unit: "")
                }
                Divider()

                SettingRow("选中框圆角", hint: "0 为方角，调大成胶囊状") {
                    numberRow($store.hilitedCornerRadius, range: 0...16, step: 1, unit: "")
                }
                Divider()

                SettingRow("窗口留白", hint: "候选窗内边距") {
                    numberRow($store.borderPadding, range: 0...20, step: 1, unit: "")
                }
                Divider()

                SettingRow("阴影大小", hint: "0 为无阴影") {
                    numberRow($store.shadowSize, range: 0...20, step: 1, unit: "")
                }
                Divider()

                SettingRow("候选间距", hint: store.isLinear
                           ? "仅竖排生效，当前为横排"
                           : "竖排时的行间距") {
                    numberRow($store.lineSpacing, range: 0...20, step: 1, unit: "")
                }
                Divider()

                SettingRow("显示候选序号") {
                    switchToggle($store.showLabel)
                }
                Divider()

                SettingRow("拼音内嵌显示", hint: "关闭后拼音单独一行") {
                    switchToggle($store.inlinePreedit)
                }
                Divider()

                SettingRow("显示翻页箭头") {
                    switchToggle($store.showPaging)
                }
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    // MARK: - 模糊音
    private var fuzzySection: some View {
        GroupBox(label: Text("模糊拼音").font(.headline)) {
            VStack(spacing: 0) {
                SettingRow("平翘舌不分", hint: "z/zh、c/ch、s/sh 可互相输入") {
                    switchToggle($store.fuzzyZhCh)
                }
                Divider()
                SettingRow("n / l 不分") {
                    switchToggle($store.fuzzyNL)
                }
                Divider()
                SettingRow("前后鼻音不分", hint: "an/ang、en/eng、in/ing") {
                    switchToggle($store.fuzzyAngAn)
                }
                Divider()
                SettingRow("f / h 不分") {
                    switchToggle($store.fuzzyFH)
                }
                Divider()
                SettingRow("g / k 不分") {
                    switchToggle($store.fuzzyGK)
                }

                if anyFuzzyOn {
                    Divider()
                    noteRow("模糊音会增加候选数量、降低精确度，按需开启",
                            icon: "info.circle", color: .orange)
                }
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    private var anyFuzzyOn: Bool {
        store.fuzzyZhCh || store.fuzzyNL || store.fuzzyAngAn
            || store.fuzzyFH || store.fuzzyGK
    }

    // MARK: - 标点与字符
    private var punctSection: some View {
        GroupBox(label: Text("标点与字符").font(.headline)) {
            VStack(spacing: 0) {
                SettingRow("中文状态用英文标点",
                           hint: "写代码、数字多的文档适合开启") {
                    switchToggle($store.asciiPunct)
                }
                Divider()
                SettingRow("默认输出繁体") {
                    switchToggle($store.traditionalDefault)
                }
                Divider()
                SettingRow("Emoji 候选", hint: "输入词语时附带表情候选") {
                    switchToggle($store.emojiOn)
                }
                Divider()
                noteRow("成对符号自动补齐由雾凇拼音内置，已默认开启",
                        icon: "keyboard", color: .secondary)
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    // MARK: - 词库
    private var dictSection: some View {
        GroupBox(label: Text("词库与记忆").font(.headline)) {
            VStack(spacing: 0) {
                SettingRow("智能调频",
                           hint: "常用词自动前排，已内置且始终开启") {
                    Text("已开启")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wxGreen)
                }
                Divider()
                SettingRow("清空输入记忆",
                           hint: "删除词频数据，候选顺序回到初始状态") {
                    Button("清空") { showClearConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                Divider()
                noteRow("全部数据保存在本地，无云端同步与热词推送",
                        icon: "lock.shield", color: Color.wxGreen)
            }
        }
        .groupBoxStyle(PlainGroupBoxStyle())
    }

    // MARK: - 复用组件

    private func switchToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .toggleStyle(.switch)
            .tint(Color.wxGreen)
            .labelsHidden()
    }

    private func numberRow(_ binding: Binding<Double>,
                           range: ClosedRange<Double>,
                           unit: String) -> some View {
        numberRow(
            Binding(
                get: { Int(binding.wrappedValue) },
                set: { binding.wrappedValue = Double($0) }
            ),
            range: Int(range.lowerBound)...Int(range.upperBound),
            step: 1,
            unit: unit
        )
    }

    /// 数字输入 + 步进按钮
    /// 滑块拖动精度差、读数要看旁边小字，改成可直接键入的数字框
    private func numberRow(_ binding: Binding<Int>,
                           range: ClosedRange<Int>,
                           step: Int,
                           unit: String) -> some View {
        // TextField 配 format 只在回车/失焦时提交，预览就跟不上输入
        // 改用字符串中转，边打字边同步，并顺手把越界值夹回区间
        let text = Binding<String>(
            get: { String(binding.wrappedValue) },
            set: { raw in
                let digits = raw.filter(\.isNumber)
                guard let v = Int(digits) else { return }
                binding.wrappedValue = min(max(v, range.lowerBound), range.upperBound)
            }
        )

        return HStack(spacing: 6) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 54)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Stepper("", value: binding, in: range, step: step)
                .labelsHidden()
        }
    }

    private func noteRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// 无外框的分组卡片样式
struct PlainGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .padding(.leading, 4)

            VStack(spacing: 0) {
                configuration.content
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}
