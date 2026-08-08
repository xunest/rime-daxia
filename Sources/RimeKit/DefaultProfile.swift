import Foundation

/// 用户的初始配置快照
/// 「恢复默认」会还原到这份配置，即最初手工调好的 macOS 风格
enum DefaultProfile {

    /// 外观：macos_light / macos_dark 两套自定义主题
    static let squirrelCustom = """
    # 鼠须管外观配置
    patch:
      config_version: '2026-08-09'

      # 亮色/暗色模式各自的主题
      style/color_scheme: macos_light
      style/color_scheme_dark: macos_dark

      # 排版为全局设置，主题内不再重复定义
      style/candidate_list_layout: linear
      style/text_orientation: horizontal
      style/font_point: 17
      style/label_font_point: 14
      style/candidate_format: "%c\\u2005%@"

      preset_color_schemes/macos_light:
        name: "macOS Light"
        author: "QoderWork"
        inline_preedit: true                 # 拼音内嵌在光标处
        corner_radius: 8
        hilited_corner_radius: 6
        border_height: 8
        border_width: 10
        spacing: 8
        font_face: "PingFangSC"
        back_color: 0xFFFFFF                 # 白色背景
        candidate_text_color: 0x262626       # 候选词深灰
        label_color: 0xA0A0A0                # 序号浅灰
        comment_text_color: 0xA0A0A0
        text_color: 0x808080
        hilited_text_color: 0x262626
        hilited_candidate_back_color: 0xFF7A00   # Apple 蓝 #007AFF
        hilited_candidate_text_color: 0xFFFFFF
        hilited_candidate_label_color: 0xFFFFFF
        hilited_comment_text_color: 0xF0F0F0

      preset_color_schemes/macos_dark:
        name: "macOS Dark"
        author: "QoderWork"
        inline_preedit: true
        corner_radius: 8
        hilited_corner_radius: 6
        border_height: 8
        border_width: 10
        spacing: 8
        font_face: "PingFangSC"
        back_color: 0x282828                 # 深灰背景
        candidate_text_color: 0xE0E0E0       # 候选词浅白
        label_color: 0x707070
        comment_text_color: 0x707070
        text_color: 0x808080
        hilited_text_color: 0xE0E0E0
        hilited_candidate_back_color: 0xFF7A00   # Apple 蓝
        hilited_candidate_text_color: 0xFFFFFF
        hilited_candidate_label_color: 0xFFFFFF
        hilited_comment_text_color: 0xF0F0F0
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

    /// 方案配置：Shift 切换中英文 + 万象语法模型
    /// 注意：不含模糊音，保持默认的精确输入
    static let schemaCustom = """
    # rime_ice 方案用户配置
    patch:
      # 注入 Shift 切换中英文处理器（放在最前面，优先处理）
      "engine/processors/@before 0": lua_processor@*shift_toggle

      # 万象语法模型（octagram 插件）：按上下文语境调整同音词顺序
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
    """

    /// 无语法模型版本：语法模型文件不存在时使用，避免部署报错
    static let schemaCustomNoGrammar = """
    # rime_ice 方案用户配置
    patch:
      # 注入 Shift 切换中英文处理器（放在最前面，优先处理）
      "engine/processors/@before 0": lua_processor@*shift_toggle
    """
}
