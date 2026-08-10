#!/bin/bash
# 把白霜的符号引导符从 / 改成 v，与雾凇统一。
#
# 为什么要改：
#   白霜官方用 / 引导符号（/fh、/dn…），但 librime 内置 preset 把 /
#   定义成半角标点（直接上屏），punctuator 匹配时单字符优先，
#   /fh 永远轮不到。上一版修法是把 / 从半角标点里删掉，
#   副作用是按 / 打不出斜杠。
#
#   改用 v 引导就没这问题：v 不是标点，不会被 punctuator 拦截，
#   而且和雾凇的用法一致，两套方案切换时不用改肌肉记忆。
#
# 连带要改计算器：
#   白霜的计算器占用 ^[Vv].*$，会吃掉所有 v 开头的输入。
#   改成和雾凇一样的 ^cC.+，把 v 让给符号。
#
# 影响范围：只改 symbols_frost.yaml 与 rime_frost.custom.yaml，
# 不动白霜原始方案文件，雾凇完全不受影响。

set -e
RIME="$HOME/Library/Rime"
OWNER="$(stat -f '%Su' "$RIME")"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
SRC="${FROST_SRC:-/tmp/rime-frost}"
# 脚本自身所在目录。用 BASH_SOURCE 而不是 $0：
# 经 osascript 提权调用时 $0 不是脚本路径，dirname 会取错。
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f "$SRC/symbols_v.yaml" ] || { echo "错误：找不到 $SRC/symbols_v.yaml"; exit 1; }

echo "==> 1/3 符号表键名 / → v"
# 从源码重新生成，避免在已改过的文件上重复替换
# 正则放在独立的 .pl 文件里：写在 shell 多层引号里极易被转义吃掉
perl "$HERE/tools/frost_symbols_to_v.pl" \
    "$SRC/symbols_v.yaml" > "$RIME/symbols_frost.yaml"

CONVERTED=$(perl -ne "\$n++ if /^\s+'v/; END{print \$n+0}" "$RIME/symbols_frost.yaml")
REMAINING=$(perl -ne "\$n++ if /^\s+'\//; END{print \$n+0}" "$RIME/symbols_frost.yaml")
echo "    已转换 $CONVERTED 个键，剩余 / 开头 $REMAINING 个"
[ "$REMAINING" = "0" ] && [ "$CONVERTED" -gt 0 ] || {
    echo "错误：键名转换未完成（转换 $CONVERTED / 残留 $REMAINING）"
    exit 1
}

echo "==> 2/3 写入方案补丁"
cat > "$RIME/rime_frost.custom.yaml" <<'EOF'
# 白霜拼音用户配置（本机试用）
patch:
  # Shift 上屏已输入的拼音。
  # 这个处理器原本只写在 rime_ice.custom.yaml 里，
  # 切到白霜后就没了，表现为按 Shift 不上屏、还得多按一次 Enter。
  "engine/processors/@before 0": lua_processor@*shift_toggle

  # 符号引导符从 / 改成 v，与雾凇统一。
  #
  # 原因：librime 内置 preset 把 / 定义成半角标点（直接上屏），
  # punctuator 匹配时单字符优先于 symbols 段的多字符条目，
  # 导致 /fh 这类符号永远触发不了。v 不是标点，没有这个问题。
  "recognizer/patterns/punct": "^v([0-9]|10|[A-Za-z]+)$"

  # 计算器让出 v：白霜原本用 ^[Vv].*$ 会吃掉所有 v 开头的输入，
  # 与符号引导冲突。改成和雾凇一致的 cC 前缀。
  "recognizer/patterns/calculator": "^cC.+"

  # 与雾凇保持一致的输入行为：中文标点、简体、开 Emoji
  "switches/@ascii_punct/reset": 0
  "switches/@traditionalization/reset": 0
  "switches/@emoji/reset": 1
EOF

chown "$OWNER:staff" "$RIME/rime_frost.custom.yaml" "$RIME/symbols_frost.yaml" 2>/dev/null || true

echo "==> 3/3 清理产物并重新部署"
rm -f "$RIME/build/rime_frost"* "$RIME/build/symbols_frost"* 2>/dev/null || true
pkill -x Squirrel 2>/dev/null || true
sleep 2
# pkill 后引擎不会自动回来，必须显式拉起
open -a "/Library/Input Methods/Squirrel.app" 2>/dev/null || true
sleep 3
"$SQUIRREL" --reload 2>/dev/null || true

echo
echo "完成。白霜现在与雾凇用法一致："
echo "  符号    vfh vdn vsx …"
echo "  计算器  cC1+2*3"
echo "  斜杠    直接按 / 即可"
