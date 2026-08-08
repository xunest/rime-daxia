import Foundation
import AppKit
import SwiftUI

/// 自测：验证 YAML 行级编辑不破坏注释与结构
/// 运行方式：RimeKit --selftest
enum SelfTest {
    static func run() -> Int32 {
        var failed = 0

        func check(_ name: String, _ cond: Bool, _ detail: String = "") {
            if cond {
                print("  PASS  \(name)")
            } else {
                print("  FAIL  \(name) \(detail)")
                failed += 1
            }
        }

        print("== YAMLLineEditor ==")

        // 1. 改值不动注释
        let src = """
        # 鼠须管外观配置
        patch:
          config_version: '2026-08-09'

          # 亮色/暗色模式各自的主题
          style/color_scheme: macos_light
          style/color_scheme_dark: macos_dark

          preset_color_schemes/macos_light:
            name: "macOS Light"
            back_color: 0xFFFFFF                 # 白色背景
        """

        var e = YAMLLineEditor(content: src)
        e.setValue("red_dark", forPath: "style/color_scheme")
        let out = e.content

        check("替换值成功", out.contains("style/color_scheme: red_dark"))
        check("保留顶部注释", out.contains("# 鼠须管外观配置"))
        check("保留段内注释", out.contains("# 亮色/暗色模式各自的主题"))
        check("保留行尾注释", out.contains("# 白色背景"))
        check("未误改 dark 项", out.contains("style/color_scheme_dark: macos_dark"))
        check("保留十六进制写法", out.contains("0xFFFFFF"))
        check("行数不变", out.components(separatedBy: "\n").count
              == src.components(separatedBy: "\n").count)

        // 2. 行尾注释在替换后依然保留
        var e2 = YAMLLineEditor(content: "  font_point: 17    # 字号")
        e2.setValue("22", forPath: "font_point")
        check("替换后保留行尾注释", e2.content.contains("22") && e2.content.contains("# 字号"),
              "得到: \(e2.content)")

        // 3. 嵌套写法读取
        let nested = """
        patch:
          style:
            color_scheme: green_dark
            font_point: 20
        """
        let e3 = YAMLLineEditor(content: nested)
        check("嵌套读取 color_scheme", e3.value(forPath: "style/color_scheme") == "green_dark",
              "得到: \(e3.value(forPath: "style/color_scheme") ?? "nil")")
        check("嵌套读取 font_point", e3.value(forPath: "style/font_point") == "20")

        // 4. 嵌套写法修改
        var e4 = YAMLLineEditor(content: nested)
        e4.setValue("blue_light", forPath: "style/color_scheme")
        check("嵌套修改生效", e4.content.contains("color_scheme: blue_light"))
        check("嵌套修改保持缩进", e4.content.contains("    color_scheme: blue_light"),
              "得到: \(e4.content)")

        // 5. 不存在的键会被追加进 patch 段
        var e5 = YAMLLineEditor(content: "patch:\n  menu/page_size: 7\n")
        e5.setValue("linear", forPath: "style/candidate_list_layout")
        check("追加新键", e5.content.contains("style/candidate_list_layout: linear"))
        check("追加后原键还在", e5.content.contains("menu/page_size: 7"))

        // 6. 引号值读取
        let quoted = "patch:\n  name: \"macOS Light\"\n  ver: '2026-08-09'\n"
        let e6 = YAMLLineEditor(content: quoted)
        check("双引号去除", e6.value(forPath: "name") == "macOS Light",
              "得到: \(e6.value(forPath: "name") ?? "nil")")
        check("单引号去除", e6.value(forPath: "ver") == "2026-08-09")

        // 7. 注释行不应被当成键匹配
        let commented = "patch:\n  # style/color_scheme: fake\n  style/color_scheme: real\n"
        let e7 = YAMLLineEditor(content: commented)
        check("跳过注释行匹配", e7.value(forPath: "style/color_scheme") == "real",
              "得到: \(e7.value(forPath: "style/color_scheme") ?? "nil")")

        print("== RimeColor (BGR) ==")

        // Rime 用 BGR：0xFF7A00 应解析为 R=0x00 G=0x7A B=0xFF，即蓝色
        if let (r, g, b) = RimeColor.parse("0xFF7A00") {
            check("BGR 顺序正确", r < 0.01 && abs(g - 0.478) < 0.01 && b > 0.99,
                  "得到 r=\(r) g=\(g) b=\(b)")
        } else {
            check("BGR 解析", false, "解析失败")
        }

        check("纯白", RimeColor.parse("0xFFFFFF").map { $0.0 > 0.99 && $0.1 > 0.99 && $0.2 > 0.99 } == true)
        check("十进制兼容", RimeColor.parse("16777215").map { $0.0 > 0.99 } == true)
        check("带引号", RimeColor.parse("'0x282828'") != nil)
        check("8 位 ABGR", RimeColor.parse("0xEEFFFFFF") != nil)

        print("== ThemeLibrary ==")

        let lib = ThemeLibrary(yamlContent: builtinThemesYAML)
        check("解析出 47 套皮肤", lib.themes.count == 47, "实际 \(lib.themes.count)")
        check("每套都有 rawBlock", lib.rawBlocks.count == lib.themes.count)
        check("包含 red_dark", lib.themes.contains { $0.id == "red_dark" })
        check("包含 wechat_light", lib.themes.contains { $0.id == "wechat_light" })
        check("包含官方 aqua", lib.themes.contains { $0.id == "aqua" })
        check("包含官方 solarized_dark", lib.themes.contains { $0.id == "solarized_dark" })
        check("包含官方 retro_green", lib.themes.contains { $0.id == "retro_green" })
        check("皮肤 ID 无重复", Set(lib.themes.map(\.id)).count == lib.themes.count)
        check("名称已解析", lib.themes.first { $0.id == "red_dark" }?.name == "夏日红-深色",
              "得到: \(lib.themes.first { $0.id == "red_dark" }?.name ?? "nil")")

        let allHaveBack = lib.themes.allSatisfy { $0.backColor != nil }
        check("所有皮肤都有背景色", allHaveBack)

        let allParseable = lib.themes.allSatisfy {
            guard let b = $0.backColor else { return false }
            return RimeColor.parse(b) != nil
        }
        check("所有背景色可解析", allParseable)

        print("== 排版冲突处理 ==")

        // 模拟真实场景：主题内有 candidate_list_layout，会覆盖全局设置
        let conflictSrc = """
        # 鼠须管外观配置
        patch:
          style/color_scheme: macos_light
          style/candidate_list_layout: stacked

          preset_color_schemes/macos_light:
            name: "macOS Light"
            candidate_list_layout: linear        # 横排候选
            font_point: 17
            back_color: 0xFFFFFF                 # 白色背景
            hilited_candidate_back_color: 0xFF7A00
        """

        let store = AppStore()
        let cleaned = store.testNeutralize(conflictSrc)

        check("主题内 layout 已注释",
              cleaned.contains("# candidate_list_layout: linear"),
              "得到:\n\(cleaned)")
        check("主题内 font_point 已注释",
              cleaned.contains("# font_point: 17"))
        check("全局 layout 未被误改",
              cleaned.contains("  style/candidate_list_layout: stacked"))
        check("颜色定义未被动",
              cleaned.contains("back_color: 0xFFFFFF")
              && !cleaned.contains("# back_color"))
        check("高亮色未被动",
              cleaned.contains("hilited_candidate_back_color: 0xFF7A00")
              && !cleaned.contains("# hilited_candidate_back_color"))
        check("name 未被动", cleaned.contains("name: \"macOS Light\""))
        check("原有注释保留", cleaned.contains("# 鼠须管外观配置"))

        // horizontal: true 也是排版字段，同样要处理
        let horizSrc = """
        patch:
          preset_color_schemes:
            red_dark:
              horizontal: true
              back_color: 0x030303
        """
        let horizCleaned = store.testNeutralize(horizSrc)
        check("主题内 horizontal 已注释",
              horizCleaned.contains("# horizontal: true"),
              "得到:\n\(horizCleaned)")

        print("== 默认配置快照 ==")

        check("外观快照含 macos_light",
              DefaultProfile.squirrelCustom.contains("preset_color_schemes/macos_light"))
        check("外观快照走全局排版",
              DefaultProfile.squirrelCustom.contains("style/candidate_list_layout: linear"))
        check("外观快照主题内无排版字段",
              !DefaultProfile.squirrelCustom
                  .components(separatedBy: "\n")
                  .contains { line in
                      let t = line.trimmingCharacters(in: .whitespaces)
                      let indent = line.prefix(while: { $0 == " " }).count
                      return indent >= 4 && (t.hasPrefix("candidate_list_layout:")
                                             || t.hasPrefix("font_point:"))
                  })
        check("设置快照候选数为 7",
              DefaultProfile.defaultCustom.contains("menu/page_size: 7"))
        check("设置快照含 Caps Lock",
              DefaultProfile.defaultCustom.contains("Caps_Lock: clear"))
        check("方案快照含语法模型",
              DefaultProfile.schemaCustom.contains("wanxiang-lts-zh-hans"))
        check("方案快照含 shift_toggle",
              DefaultProfile.schemaCustom.contains("shift_toggle"))
        check("方案快照不含模糊音",
              !DefaultProfile.schemaCustom.contains("derive/"))

        // 三份快照都得是合法的 patch 结构
        for (name, text) in [("外观", DefaultProfile.squirrelCustom),
                             ("设置", DefaultProfile.defaultCustom),
                             ("方案", DefaultProfile.schemaCustom)] {
            check("\(name)快照以 patch: 开头",
                  text.components(separatedBy: "\n")
                      .contains { $0.trimmingCharacters(in: .whitespaces) == "patch:" })
        }

        print("== 透明度 alpha 通道 ==")

        let opacitySrc = """
        patch:
          style/color_scheme: macos_light
          preset_color_schemes/macos_light:
            name: "macOS Light"
            back_color: 0xFFFFFF                 # 白色背景
            candidate_text_color: 0x262626
        """
        let s2 = AppStore()
        s2.useCustomColors = false
        s2.selectedThemeID = "macos_light"
        s2.selectedDarkThemeID = "macos_dark"
        let op80 = s2.testApplyOpacity(opacitySrc, opacity: 80)

        // 80% → alpha = 204 = 0xCC
        check("80% 透明度写入 0xCC",
              op80.contains("back_color: 0xCCFFFFFF"),
              "得到:\n\(op80)")
        check("透明度不动其他颜色",
              op80.contains("candidate_text_color: 0x262626"))
        check("透明度保留行尾注释",
              op80.contains("# 白色背景"))

        // 100% 应该是完全不透明
        let op100 = s2.testApplyOpacity(opacitySrc, opacity: 100)
        check("100% 写入 0xFF", op100.contains("back_color: 0xFFFFFFFF"))

        // 已有 alpha 的情况应该被替换而非叠加
        let hasAlphaSrc = """
        patch:
          preset_color_schemes/macos_light:
            back_color: 0xCCFFFFFF
        """
        let reApplied = s2.testApplyOpacity(hasAlphaSrc, opacity: 50)
        check("已有 alpha 被正确替换",
              reApplied.contains("back_color: 0x7FFFFFFF"),
              "得到: \(reApplied)")
        check("不会叠加成超长十六进制",
              !reApplied.contains("0x7FCCFFFFFF"))

        print("== 透明度反推 ==")

        check("从 0xCCFFFFFF 反推出 80",
              RimeColor.parse("0xCCFFFFFF") != nil)

        print("== 模糊音规则 ==")

        let s3 = AppStore()
        // 显式重置所有开关，避免读到本机真实配置影响判断
        s3.fuzzyZhCh = false
        s3.fuzzyNL = false
        s3.fuzzyFH = false
        s3.fuzzyGK = false
        s3.fuzzyAngAn = false

        s3.fuzzyZhCh = true
        s3.fuzzyFH = true
        let fuzzyOut = s3.testFuzzyRules()
        check("平翘舌规则正确", fuzzyOut.contains("derive/^([zcs])h/$1/"))
        check("f/h 规则正确", fuzzyOut.contains("derive/^f/h/"))
        check("未开启的不写入", !fuzzyOut.contains("derive/^g/k/"))
        check("未开启前后鼻音不写入", !fuzzyOut.contains("derive/ang$/an/"))

        // 全开时规则数量应为 2+2+2+2+6 = 14
        s3.fuzzyNL = true
        s3.fuzzyGK = true
        s3.fuzzyAngAn = true
        let allRules = s3.testFuzzyRules().components(separatedBy: "\n")
        check("全开时 14 条规则", allRules.count == 14, "实际 \(allRules.count)")

        // 全关时应为空
        s3.fuzzyZhCh = false
        s3.fuzzyNL = false
        s3.fuzzyFH = false
        s3.fuzzyGK = false
        s3.fuzzyAngAn = false
        check("全关时无规则", s3.testFuzzyRules().isEmpty)

        print("== 职责分离：换皮肤不动候选窗设置 ==")

        // 用户已有配置：横排、字号 20、候选 5 个
        let userConfig = """
        # 我的配置
        patch:
          style/color_scheme: macos_light
          style/color_scheme_dark: macos_dark
          style/font_point: 20                 # 我调大的字号
          style/label_font_point: 15
          style/candidate_list_layout: linear
          style/text_orientation: horizontal
          style/corner_radius: 12
          style/line_spacing: 8
          style/inline_preedit: true
          style/show_paging: false

          preset_color_schemes/macos_light:
            name: "macOS Light"
            back_color: 0xFFFFFF
            candidate_text_color: 0x262626
        """

        let s4 = AppStore()
        s4.opacity = 100
        s4.useCustomColors = false
        // 模拟用户在界面上把皮肤换成另一套
        s4.selectedThemeID = "aqua"
        s4.selectedDarkThemeID = "macos_dark"
        let afterSkin = s4.themeResult(from: userConfig)

        check("换皮肤后 color_scheme 已更新",
              afterSkin.contains("style/color_scheme: aqua"),
              "得到:\n\(afterSkin)")
        check("换皮肤不动字号",
              afterSkin.contains("style/font_point: 20"))
        check("换皮肤不动序号字号",
              afterSkin.contains("style/label_font_point: 15"))
        check("换皮肤不动排列方向",
              afterSkin.contains("style/candidate_list_layout: linear"))
        check("换皮肤不动圆角",
              afterSkin.contains("style/corner_radius: 12"))
        check("换皮肤不动行距",
              afterSkin.contains("style/line_spacing: 8"))
        check("换皮肤保留字号注释",
              afterSkin.contains("# 我调大的字号"))
        check("换皮肤保留文件头注释",
              afterSkin.contains("# 我的配置"))

        print("== 职责分离：改候选窗不动皮肤 ==")

        let s5 = AppStore()
        s5.opacity = 100
        s5.useCustomColors = false
        s5.selectedThemeID = "macos_light"
        s5.selectedDarkThemeID = "macos_dark"
        s5.fontSize = 24
        s5.labelFontSize = 16
        s5.layout = .vertical        // 改成竖排（文字仍水平）
        s5.cornerRadius = 4
        s5.lineSpacing = 10
        s5.inlinePreedit = false
        s5.showPaging = true
        let afterStyle = s5.candidateStyleResult(from: userConfig)

        check("改候选窗后字号已更新",
              afterStyle.contains("style/font_point: 24"),
              "得到:\n\(afterStyle)")
        check("改候选窗后变竖排",
              afterStyle.contains("style/candidate_list_layout: stacked"))
        check("普通竖排文字保持水平",
              afterStyle.contains("style/text_orientation: horizontal"),
              "得到:\n\(afterStyle)")
        check("改候选窗后圆角已更新",
              afterStyle.contains("style/corner_radius: 4"))
        check("拼音内嵌可关闭",
              afterStyle.contains("style/inline_preedit: false"))
        check("翻页箭头可开启",
              afterStyle.contains("style/show_paging: true"))
        check("改候选窗不动浅色皮肤",
              afterStyle.contains("style/color_scheme: macos_light"))
        check("改候选窗不动深色皮肤",
              afterStyle.contains("style/color_scheme_dark: macos_dark"))
        check("改候选窗不动主题颜色",
              afterStyle.contains("back_color: 0xFFFFFF")
              && afterStyle.contains("candidate_text_color: 0x262626"))

        print("== 自定义配色 ==")

        // 颜色往返：Rime 是 BGR，转回来必须一致
        let red = Color(red: 1, green: 0, blue: 0)
        check("纯红转 Rime BGR", red.rimeHex == "0x0000FF", "得到 \(red.rimeHex)")
        let blue = Color(red: 0, green: 0, blue: 1)
        check("纯蓝转 Rime BGR", blue.rimeHex == "0xFF0000", "得到 \(blue.rimeHex)")
        if let (r, g, b) = RimeColor.parse(red.rimeHex) {
            check("红色往返一致", r > 0.99 && g < 0.01 && b < 0.01)
        } else {
            check("红色往返一致", false, "解析失败")
        }

        let s6 = AppStore()
        s6.opacity = 100
        s6.useCustomColors = true
        s6.customLight = CustomScheme(
            back: Color(red: 1, green: 1, blue: 1),
            candidateText: Color(red: 0, green: 0, blue: 0),
            hilitedText: Color(red: 1, green: 1, blue: 1),
            hilitedBack: Color(red: 1, green: 0, blue: 0),
            label: Color(red: 0.5, green: 0.5, blue: 0.5)
        )

        let customBlock = s6.customLight.yamlBlock(id: CustomScheme.lightID, name: "自定义-浅色")
        check("自定义块含方案 ID", customBlock.contains("\(CustomScheme.lightID):"))
        check("自定义块写入背景色", customBlock.contains("back_color: 0xFFFFFF"))
        check("自定义块选中背景为 BGR 红", customBlock.contains("hilited_candidate_back_color: 0x0000FF"),
              "得到:\n\(customBlock)")

        // 自定义模式下 color_scheme 应指向自定义方案，而非列表选中项
        let baseCfg = "# 我的配置\npatch:\n  style/color_scheme: macos_light\n  style/font_point: 20\n"
        let customOut = s6.themeResult(from: baseCfg)
        check("自定义模式指向自定义方案",
              customOut.contains("style/color_scheme: \(CustomScheme.lightID)"),
              "得到:\n\(customOut)")
        check("自定义模式不动字号", customOut.contains("style/font_point: 20"))
        check("自定义模式保留注释", customOut.contains("# 我的配置"))

        // 关掉自定义应回到预设
        s6.useCustomColors = false
        s6.selectedThemeID = "ink"
        check("关闭自定义回到预设",
              s6.themeResult(from: baseCfg).contains("style/color_scheme: ink"))

        // upsert：已存在的块要被整块替换，不能重复插入
        let existing = """
        patch:
          preset_color_schemes:
            \(CustomScheme.lightID):
              name: "旧的"
              back_color: 0x000000
            ink:
              name: "墨池"
        """
        let replaced = s6.upsertThemeBlock(
            s6.customLight.yamlBlock(id: CustomScheme.lightID, name: "自定义-浅色"),
            themeID: CustomScheme.lightID, into: existing)
        check("upsert 替换旧值", replaced.contains("back_color: 0xFFFFFF"),
              "得到:\n\(replaced)")
        check("upsert 清掉旧内容", !replaced.contains("name: \"旧的\""))
        check("upsert 不重复插入",
              replaced.components(separatedBy: "\(CustomScheme.lightID):").count == 2)
        check("upsert 不影响相邻块", replaced.contains("name: \"墨池\""))

        print("== 选中背景与候选窗同色 ==")

        var plain = CustomScheme(
            back: Color(red: 1, green: 1, blue: 1),
            candidateText: Color(red: 0, green: 0, blue: 0),
            hilitedText: Color(red: 1, green: 0, blue: 0),
            hilitedBack: Color(red: 0, green: 0, blue: 1),
            label: Color(red: 0.5, green: 0.5, blue: 0.5)
        )
        check("默认使用自选背景", plain.effectiveHilitedBack.rimeHex == "0xFF0000",
              "得到 \(plain.effectiveHilitedBack.rimeHex)")

        plain.plainHilite = true
        check("同色时取候选窗背景", plain.effectiveHilitedBack.rimeHex == "0xFFFFFF",
              "得到 \(plain.effectiveHilitedBack.rimeHex)")

        let plainBlock = plain.yamlBlock(id: "t", name: "测试")
        check("同色时写入窗口背景色",
              plainBlock.contains("hilited_candidate_back_color: 0xFFFFFF"),
              "得到:\n\(plainBlock)")
        check("同色时选中字色保留",
              plainBlock.contains("hilited_candidate_text_color: 0x0000FF"))

        // 从无底色皮肤取色时应自动勾选
        let flatTheme = Theme(
            id: "flat", name: "无底色", author: "",
            backColor: "0x222222",
            candidateTextColor: "0xEEEEEE",
            hilitedCandidateBackColor: "0x222222",
            hilitedCandidateTextColor: "0x00FF00",
            labelColor: "0x888888",
            commentTextColor: nil, borderColor: nil,
            fontPoint: nil, cornerRadius: nil, isLinear: true
        )
        check("无底色皮肤自动勾选同色",
              CustomScheme(from: flatTheme, fallback: .defaultDark).plainHilite)

        let solidTheme = Theme(
            id: "solid", name: "有底色", author: "",
            backColor: "0x222222",
            candidateTextColor: "0xEEEEEE",
            hilitedCandidateBackColor: "0xFF7A00",
            hilitedCandidateTextColor: "0xFFFFFF",
            labelColor: "0x888888",
            commentTextColor: nil, borderColor: nil,
            fontPoint: nil, cornerRadius: nil, isLinear: true
        )
        check("有底色皮肤不勾选同色",
              !CustomScheme(from: solidTheme, fallback: .defaultDark).plainHilite)

        print("== 候选序号显隐 ==")

        // 皮肤自带 candidate_format / label_font_point 会盖掉全局设置，
        // 这正是「开启序号有时不生效」的原因
        let labelSrc = """
        patch:
          style/color_scheme: sogou
          preset_color_schemes/sogou:
            name: "搜狗"
            candidate_format: "%@"
            label_font_point: 1
            back_color: 0xFFFFFF
        """

        let s7 = AppStore()
        s7.opacity = 100
        s7.useCustomColors = false
        s7.selectedThemeID = "sogou"
        s7.selectedDarkThemeID = "macos_dark"
        s7.labelFontSize = 14
        s7.showLabel = true
        let labelOn = s7.candidateStyleResult(from: labelSrc)

        check("开启序号写入 %c",
              labelOn.contains("style/candidate_format:") && labelOn.contains("%c"),
              "得到:\n\(labelOn)")
        check("皮肤内 candidate_format 被注释",
              labelOn.contains("# candidate_format: \"%@\""),
              "得到:\n\(labelOn)")
        check("皮肤内 label_font_point 被注释",
              labelOn.contains("# label_font_point: 1"))
        check("全局序号字号生效",
              labelOn.contains("style/label_font_point: 14"))
        check("注释未误伤颜色",
              labelOn.contains("back_color: 0xFFFFFF") && !labelOn.contains("# back_color"))

        // 关闭序号：格式里不能有 %c
        s7.showLabel = false
        let labelOff = s7.candidateStyleResult(from: labelSrc)
        check("关闭序号不含 %c",
              !(YAMLLineEditor(content: labelOff).value(forPath: "style/candidate_format") ?? "")
                  .contains("%c"),
              "得到: \(YAMLLineEditor(content: labelOff).value(forPath: "style/candidate_format") ?? "nil")")

        // label_font_point 不能被 font_point 前缀误匹配
        let fontSrc = """
        patch:
          preset_color_schemes/x:
            font_point: 20
            label_font_point: 12
        """
        let fontCleaned = s7.testNeutralize(fontSrc)
        check("font_point 与 label_font_point 各自被注释",
              fontCleaned.contains("# font_point: 20")
              && fontCleaned.contains("# label_font_point: 12"),
              "得到:\n\(fontCleaned)")

        check("默认快照序号走全局",
              DefaultProfile.squirrelCustom.contains("style/candidate_format:"))
        check("默认快照主题内无 candidate_format",
              !DefaultProfile.squirrelCustom
                  .components(separatedBy: "\n")
                  .contains { line in
                      let t = line.trimmingCharacters(in: .whitespaces)
                      let indent = line.prefix(while: { $0 == " " }).count
                      return indent >= 4 && t.hasPrefix("candidate_format:")
                  })

        print("== 候选词字体 ==")

        check("字体库非空", !FontLibrary.chineseFamilies.isEmpty,
              "实际 \(FontLibrary.chineseFamilies.count)")
        check("字体库含苹方", FontLibrary.chineseFamilies.contains("PingFang SC"))
        check("字体库无重复",
              Set(FontLibrary.chineseFamilies).count == FontLibrary.chineseFamilies.count)

        // 分类：黑体、宋体、楷体、行书都要有内容，否则挑字体没意义
        let groups = Dictionary(uniqueKeysWithValues: FontLibrary.grouped.map { ($0.0, $0.1) })
        check("有黑体分类", !(groups[.sans] ?? []).isEmpty)
        check("有宋体分类", !(groups[.serif] ?? []).isEmpty)
        check("有楷体分类", !(groups[.kai] ?? []).isEmpty)
        check("有行书分类", !(groups[.script] ?? []).isEmpty)

        check("苹方归入黑体",
              groups[.sans]?.contains { $0.family == "PingFang SC" } == true)
        check("楷体归入楷体类",
              groups[.kai]?.contains { $0.family == "Kaiti SC" } == true)
        check("宋体归入宋体类",
              groups[.serif]?.contains { $0.family == "Songti SC" } == true)
        check("行楷归入行书类",
              groups[.script]?.contains { $0.family == "Xingkai SC" } == true)

        check("分组总数与扁平列表一致",
              FontLibrary.grouped.reduce(0) { $0 + $1.1.count } == FontLibrary.choices.count)
        check("每个分类内无重复",
              FontLibrary.grouped.allSatisfy { Set($0.1).count == $0.1.count })
        check("苹方在黑体类置顶",
              groups[.sans]?.first?.family == "PingFang SC",
              "得到 \(groups[.sans]?.first?.family ?? "nil")")

        // 皮肤自带 font_face，用户指定字体时必须被中和
        let fontFaceSrc = """
        patch:
          style/color_scheme: sogou
          preset_color_schemes/sogou:
            name: "搜狗"
            font_face: HiraginoSansCNS-W3
            label_font_face: HiraginoSansCNS-W3
            back_color: 0xFFFFFF
        """

        let s8 = AppStore()
        s8.opacity = 100
        s8.useCustomColors = false
        s8.selectedThemeID = "sogou"
        s8.selectedDarkThemeID = "macos_dark"

        s8.fontFace = "Kaiti SC"
        let withFont = s8.candidateStyleResult(from: fontFaceSrc)
        check("指定字体写入全局",
              withFont.contains("style/font_face: \"Kaiti SC\""),
              "得到:\n\(withFont)")
        check("指定字体时中和皮肤字体",
              withFont.contains("# font_face: HiraginoSansCNS-W3"),
              "得到:\n\(withFont)")
        check("同时中和序号字体",
              withFont.contains("# label_font_face: HiraginoSansCNS-W3"))
        check("字体中和不误伤颜色",
              withFont.contains("back_color: 0xFFFFFF") && !withFont.contains("# back_color"))

        // 跟随皮肤时不接管字体，皮肤自带的应保持原样
        s8.fontFace = ""
        let noFont = s8.candidateStyleResult(from: fontFaceSrc)
        check("跟随皮肤不写 font_face",
              YAMLLineEditor(content: noFont).value(forPath: "style/font_face") == nil,
              "得到 \(YAMLLineEditor(content: noFont).value(forPath: "style/font_face") ?? "nil")")
        check("跟随皮肤保留皮肤字体",
              noFont.contains("font_face: HiraginoSansCNS-W3")
              && !noFont.contains("# font_face"),
              "得到:\n\(noFont)")
        check("跟随皮肤仍中和字号",
              noFont.contains("style/font_point:"))

        print("== 候选窗排版模式 ==")

        check("三种排版模式", CandidateLayout.allCases.count == 3)

        check("横排 → linear + horizontal",
              CandidateLayout.horizontal.listLayout == "linear"
              && CandidateLayout.horizontal.textOrientation == "horizontal")
        check("竖排 → stacked + horizontal",
              CandidateLayout.vertical.listLayout == "stacked"
              && CandidateLayout.vertical.textOrientation == "horizontal")
        check("竖排竖文 → stacked + vertical",
              CandidateLayout.verticalText.listLayout == "stacked"
              && CandidateLayout.verticalText.textOrientation == "vertical")

        check("只有横排按一行预览",
              CandidateLayout.horizontal.isLinear
              && !CandidateLayout.vertical.isLinear
              && !CandidateLayout.verticalText.isLinear)

        // 从配置还原：三种组合都要能正确识别
        check("还原横排",
              CandidateLayout.from(listLayout: "linear", textOrientation: "horizontal") == .horizontal)
        check("还原竖排",
              CandidateLayout.from(listLayout: "stacked", textOrientation: "horizontal") == .vertical)
        check("还原竖排竖文",
              CandidateLayout.from(listLayout: "stacked", textOrientation: "vertical") == .verticalText)
        check("缺字段默认横排",
              CandidateLayout.from(listLayout: nil, textOrientation: nil) == .horizontal)
        check("linear 时忽略 vertical 文字方向",
              CandidateLayout.from(listLayout: "linear", textOrientation: "vertical") == .horizontal)

        // 竖排竖文要真的写出 vertical
        let s9 = AppStore()
        s9.opacity = 100
        s9.useCustomColors = false
        s9.selectedThemeID = "macos_light"
        s9.selectedDarkThemeID = "macos_dark"
        s9.layout = .verticalText
        let vtOut = s9.candidateStyleResult(from: "patch:\n  style/color_scheme: macos_light\n")
        check("竖排竖文写入 stacked",
              vtOut.contains("style/candidate_list_layout: stacked"))
        check("竖排竖文写入 vertical",
              vtOut.contains("style/text_orientation: vertical"),
              "得到:\n\(vtOut)")

        s9.layout = .horizontal
        let hOut = s9.candidateStyleResult(from: "patch:\n  style/color_scheme: macos_light\n")
        check("横排写入 linear",
              hOut.contains("style/candidate_list_layout: linear"))
        check("横排写入 horizontal",
              hOut.contains("style/text_orientation: horizontal"))

        print("== 预览参数联动 ==")

        // 预览必须收到所有影响外观的参数，否则调了看不到变化
        let pvTheme = ThemeLibrary(yamlContent: builtinThemesYAML).themes[0]
        let pv = CandidatePreview(
            theme: pvTheme,
            fontSize: 22, labelFontSize: 14,
            isLinear: true, showLabel: true,
            cornerRadius: 8, lineSpacing: 5,
            opacity: 60, pageSize: 7,
            fontFace: "Kaiti SC",
            inlinePreedit: false, showPaging: true
        )
        check("预览接收不透明度", pv.opacity == 60)
        check("预览接收圆角", pv.cornerRadius == 8)
        check("预览接收行距", pv.lineSpacing == 5)
        check("预览接收拼音内嵌", pv.inlinePreedit == false)
        check("预览接收翻页箭头", pv.showPaging == true)
        check("预览接收字体", pv.fontFace == "Kaiti SC")

        // 选中框圆角、阴影、留白三项要能独立写入
        let s12 = AppStore()
        s12.opacity = 100
        s12.useCustomColors = false
        s12.selectedThemeID = "macos_light"
        s12.selectedDarkThemeID = "macos_dark"
        s12.hilitedCornerRadius = 12
        s12.shadowSize = 6
        s12.borderPadding = 10
        let chrome = s12.candidateStyleResult(from: "patch:\n  style/color_scheme: macos_light\n")
        check("写入选中框圆角",
              chrome.contains("style/hilited_corner_radius: 12"), "得到:\n\(chrome)")
        check("写入阴影大小", chrome.contains("style/shadow_size: 6"))
        check("留白同时写宽高",
              chrome.contains("style/border_width: 10")
              && chrome.contains("style/border_height: 10"))

        // 皮肤自带这三项时也要被中和
        let chromeSrc = """
        patch:
          style/color_scheme: sogou
          preset_color_schemes/sogou:
            name: "搜狗"
            hilited_corner_radius: 3
            border_width: 2
            border_height: 2
            shadow_size: 1
            back_color: 0xFFFFFF
        """
        s12.selectedThemeID = "sogou"
        let chromeN = s12.candidateStyleResult(from: chromeSrc)
        check("中和皮肤留白",
              chromeN.contains("# border_width: 2") && chromeN.contains("# border_height: 2"),
              "得到:\n\(chromeN)")
        check("中和皮肤阴影", chromeN.contains("# shadow_size: 1"))

        // 翻页箭头要真的写进配置
        let s10 = AppStore()
        s10.opacity = 100
        s10.useCustomColors = false
        s10.selectedThemeID = "macos_light"
        s10.selectedDarkThemeID = "macos_dark"
        s10.showPaging = true
        let pgOn = s10.candidateStyleResult(from: "patch:\n  style/color_scheme: macos_light\n")
        check("开启翻页箭头写入 true",
              pgOn.contains("style/show_paging: true"), "得到:\n\(pgOn)")
        s10.showPaging = false
        let pgOff = s10.candidateStyleResult(from: "patch:\n  style/color_scheme: macos_light\n")
        check("关闭翻页箭头写入 false",
              pgOff.contains("style/show_paging: false"))

        // 皮肤自带圆角/行距会盖掉全局设置，必须中和
        let radiusSrc = """
        patch:
          style/color_scheme: sogou
          preset_color_schemes/sogou:
            name: "搜狗"
            corner_radius: 16
            hilited_corner_radius: 12
            line_spacing: 3
            back_color: 0xFFFFFF
        """
        let s11 = AppStore()
        s11.opacity = 100
        s11.useCustomColors = false
        s11.selectedThemeID = "sogou"
        s11.selectedDarkThemeID = "macos_dark"
        s11.cornerRadius = 6
        let rOut = s11.candidateStyleResult(from: radiusSrc)
        check("中和皮肤圆角", rOut.contains("# corner_radius: 16"), "得到:\n\(rOut)")
        check("中和皮肤选中圆角", rOut.contains("# hilited_corner_radius: 12"))
        check("中和皮肤行距", rOut.contains("# line_spacing: 3"))
        check("全局圆角生效", rOut.contains("style/corner_radius: 6"))
        check("圆角中和不误伤颜色",
              rOut.contains("back_color: 0xFFFFFF") && !rOut.contains("# back_color"))

        print("== 应用信息 ==")

        check("应用名称为大侠输入法", AppInfo.name == "大侠输入法")
        check("BundleID 已更新", AppInfo.bundleID == "com.daxia.ime.kit")

        print("== 安装器 ==")

        // 引擎必须装成 Squirrel.app：Info.plist 里的
        // InputMethodServerControllerClass 带 Squirrel. 模块名前缀，
        // 改 bundle 名会让 InputMethodKit 找不到控制器类
        check("引擎安装路径正确",
              Installer.engineDest == "/Library/Input Methods/Squirrel.app")
        // 输入源 ID 必须带 .Hans 后缀：不带后缀的父级 bundle
        // IsSelectCapable 为 false，选它不会生效，装完切不过去
        check("输入源 ID 带 Hans 后缀",
              Installer.inputSourceID == "im.rime.inputmethod.Squirrel.Hans",
              "得到: \(Installer.inputSourceID)")
        check("输入源 ID 不是父级 bundle",
              Installer.inputSourceID != "im.rime.inputmethod.Squirrel")
        // 写入偏好时 Bundle ID 用父级、Input Mode 用带后缀的，
        // 这与系统在设置里手动添加时写入的结构一致
        check("引擎 bundle ID 是父级",
              Installer.engineBundleID == "im.rime.inputmethod.Squirrel")
        check("输入源 ID 以引擎 bundle ID 为前缀",
              Installer.inputSourceID.hasPrefix(Installer.engineBundleID + "."))

        // 只补缺失项：对方已有的词库和设置不能被覆盖
        let fm = FileManager.default
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selftest-merge-\(UUID().uuidString)")
        let srcDir = sandbox.appendingPathComponent("src")
        let dstDir = sandbox.appendingPathComponent("dst")
        try? fm.createDirectory(at: srcDir.appendingPathComponent("cn_dicts"),
                                withIntermediateDirectories: true)
        try? fm.createDirectory(at: dstDir.appendingPathComponent("cn_dicts"),
                                withIntermediateDirectories: true)

        // 新文件：目标端没有，应被补入
        try? "new".write(to: srcDir.appendingPathComponent("rime_ice.schema.yaml"),
                         atomically: true, encoding: .utf8)
        // 冲突文件：两边都有，应保留目标端内容
        try? "packed".write(to: srcDir.appendingPathComponent("default.yaml"),
                            atomically: true, encoding: .utf8)
        try? "mine".write(to: dstDir.appendingPathComponent("default.yaml"),
                          atomically: true, encoding: .utf8)
        // 子目录内的新文件也要能补进去
        try? "dict".write(to: srcDir.appendingPathComponent("cn_dicts/base.dict.yaml"),
                          atomically: true, encoding: .utf8)
        // 目标端独有的文件不能被删
        try? "userword".write(to: dstDir.appendingPathComponent("custom_phrase.txt"),
                              atomically: true, encoding: .utf8)

        Installer.testMergeMissing(from: srcDir, to: dstDir)

        func read(_ u: URL) -> String {
            (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        }
        check("补入缺失文件",
              fm.fileExists(atPath: dstDir.appendingPathComponent("rime_ice.schema.yaml").path))
        check("不覆盖已有文件",
              read(dstDir.appendingPathComponent("default.yaml")) == "mine",
              "得到: \(read(dstDir.appendingPathComponent("default.yaml")))")
        check("补入子目录内缺失文件",
              fm.fileExists(atPath: dstDir.appendingPathComponent("cn_dicts/base.dict.yaml").path))
        check("保留目标端独有文件",
              read(dstDir.appendingPathComponent("custom_phrase.txt")) == "userword")

        try? fm.removeItem(at: sandbox)

        // 预设配置必须齐备，否则新机器装完是雾凇裸配置，
        // 用不上我们调好的主题与候选数
        check("预设含外观配置",
              DefaultProfile.squirrelCustom.contains("patch:"))
        check("预设含输入设置",
              DefaultProfile.defaultCustom.contains("patch:"))
        check("预设含方案配置",
              DefaultProfile.schemaCustom.contains("patch:"))
        // 语法模型缺失时要有备用版本，否则部署报错
        check("无语法模型的备用预设不含 grammar",
              !DefaultProfile.schemaCustomNoGrammar.contains("grammar:"))

        print("== 图标绘制 ==")

        // 各尺寸都要能画出有效图像，.icns 才不会缺档
        for px in [16, 32, 128, 256, 512, 1024] {
            let icon = AppIcon.render(size: CGFloat(px))
            check("图标 \(px)px 尺寸正确",
                  Int(icon.size.width) == px && Int(icon.size.height) == px,
                  "实际 \(icon.size)")
            check("图标 \(px)px 可转 PNG",
                  icon.tiffRepresentation
                      .flatMap { NSBitmapImageRep(data: $0) }
                      .flatMap { $0.representation(using: .png, properties: [:]) } != nil)
        }

        print("")
        if failed == 0 {
            print("全部通过")
        } else {
            print("\(failed) 项失败")
        }
        return failed == 0 ? 0 : 1
    }
}
