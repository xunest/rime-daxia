import Foundation

/// 用户的初始配置快照
/// 「恢复默认」会还原到这份配置，首次安装铺设的也是它
enum DefaultProfile {

    /// 外观：daxia_custom / daxia_custom_dark 两套自定义配色
    ///
    /// 不写 style/font_face：手札体等附加字体属于 macOS 按需下载，
    /// 新机器上没有，写死会静默回退且与预期不符。留空即跟随系统字体，
    /// 用户想换字体在「输入设置」里选。
    static let squirrelCustom = """
    # 鼠须管外观配置
    patch:
      config_version: '2026-08-09'

      # 亮色/暗色模式各自的主题
      style/color_scheme: daxia_custom
      style/color_scheme_dark: daxia_custom_dark

      # 排版为全局设置，主题内不再重复定义
      style/candidate_list_layout: linear
      style/text_orientation: horizontal
      style/font_point: 21
      style/label_font_point: 20
      style/candidate_format: "%c\\u2005%@"
      style/corner_radius: 8
      style/hilited_corner_radius: 10
      style/shadow_size: 0
      style/border_width: 0
      style/border_height: 0
      style/line_spacing: 5
      style/inline_preedit: true
      style/show_paging: false
      style/translucency: false

      # 必须写成嵌套的 preset_color_schemes: 段，不能用
      # `preset_color_schemes/xxx:` 扁平路径。后者 librime 认，但界面的
      # ThemeLibrary 靠定位 `preset_color_schemes:` 段来解析主题，
      # 扁平写法会导致解析不到，恢复默认后预览与取色器读不出颜色。
      preset_color_schemes:
        daxia_custom:
          name: "自定义-浅色"
          author: 大侠输入法
          back_color: 0xFFF4F4F6
          candidate_text_color: 0x222222
          hilited_candidate_text_color: 0x4F11FA
          hilited_candidate_back_color: 0xC7F1D2
          hilited_candidate_label_color: 0x4F11FA
          label_color: 0x939100
          comment_text_color: 0x939100
          text_color: 0x939100
          hilited_text_color: 0x222222
          hilited_back_color: 0xF4F4F6
          border_color: 0xF4F4F6

        daxia_custom_dark:
          name: "自定义-深色"
          author: 大侠输入法
          back_color: 0xFF000000
          candidate_text_color: 0xFFFFFF
          hilited_candidate_text_color: 0xFFFFFF
          hilited_candidate_back_color: 0xD75A00
          hilited_candidate_label_color: 0xFFFFFF
          label_color: 0x999999
          comment_text_color: 0x999999
          text_color: 0x999999
          hilited_text_color: 0xFFFFFF
          hilited_back_color: 0x000000
          border_color: 0x000000
    """

    /// 常用设置：只保留雾凇全拼、候选 7 个、Caps Lock 切英文
    static let defaultCustom = """
    # 鼠须管用户配置（覆盖 default.yaml）
    patch:
      # 只保留雾凇拼音全拼方案
      schema_list:
        - schema: rime_ice    # 雾凇拼音（全拼）

      # 候选词数量
      menu/page_size: 7

      # Caps Lock 切换英文（保持系统输入法的使用习惯）
      ascii_composer/switch_key:
        Caps_Lock: clear
        Shift_L: noop
        Shift_R: noop
        Control_L: noop
        Control_R: noop
    """

    /// 语法模型补丁块（带标记，供开关读写）
    static let grammarPatchBlock = """
      # >>> RimeKit 语法模型 开始 <<<
      grammar:
        language: wanxiang-lts-zh-hans
        collocation_max_length: 6
        collocation_min_length: 3
        collocation_penalty: -14
        non_collocation_penalty: -6
        weak_collocation_penalty: -100
        rear_penalty: -20
      translator/contextual_suggestions: false
      translator/max_homophones: 8
      # >>> RimeKit 语法模型 结束 <<<
    """

    /// 语法模型补丁按行拆分，写入时用
    static var grammarPatchLines: [String] {
        grammarPatchBlock
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    /// 模糊音补丁块（带标记，供开关读写）
    /// 默认开启平翘舌与 n/l 不分，覆盖最常见的南方发音习惯
    static let fuzzyPatchBlock = """
      # >>> RimeKit 模糊音 开始 <<<
      speller/algebra/+:
        - derive/^([zcs])h/$1/
        - derive/^([zcs])([^h])/$1h$2/
        - derive/^l/n/
        - derive/^n/l/
      # >>> RimeKit 模糊音 结束 <<<
    """

    /// 输入行为补丁块：中文标点、简体、开 Emoji
    /// 字段顺序与 AppStore.writePunctuation 保持一致，便于开关回读
    static let punctPatchBlock = """
      # >>> RimeKit 输入行为 开始 <<<
      "switches/@ascii_punct/reset": 0
      "switches/@traditionalization/reset": 0
      "switches/@emoji/reset": 1
      # >>> RimeKit 输入行为 结束 <<<
    """

    /// Shift 切换中英文的处理器块（带标记）
    static let shiftPatchBlock = """
      # >>> RimeKit Shift切换 开始 <<<
      "engine/processors/@before 0": lua_processor@*shift_toggle
      # >>> RimeKit Shift切换 结束 <<<
    """

    /// 方案配置：Shift 切换中英文 + 万象语法模型 + 模糊音 + 输入行为
    static let schemaCustom = """
    # rime_ice 方案用户配置
    patch:
    """ + "\n" + shiftPatchBlock + "\n" + grammarPatchBlock + "\n"
        + fuzzyPatchBlock + "\n" + punctPatchBlock + "\n"

    /// 无语法模型版本：语法模型文件不存在时使用，避免部署报错
    static let schemaCustomNoGrammar = """
    # rime_ice 方案用户配置
    patch:
    """ + "\n" + shiftPatchBlock + "\n" + fuzzyPatchBlock + "\n"
        + punctPatchBlock + "\n"
}
