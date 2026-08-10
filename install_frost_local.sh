#!/bin/bash
# 在保留雾凇的前提下，把白霜拼音装成第二套方案（仅本机试用，不进产品包）。
#
# 为什么需要这个脚本：
#   白霜（rime-frost）由雾凇（rime-ice）修改而来，两者都假定独占
#   ~/Library/Rime。白霜引用的 15 个 lua 里有 11 个与雾凇同名但内容不同
#   （lunar 差 746 行、corrector 差 283 行），symbols_v.yaml 也冲突
#   （雾凇用 v 开头的键、白霜用 / 开头）。直接按官方文档覆盖安装
#   会静默改掉雾凇的行为。
#
# 做法：
#   白霜的 lua 全部放进 lua/frost/，符号表另存为 symbols_frost.yaml，
#   再把白霜方案里的引用批量改写指向这些独立副本。
#   雾凇的任何文件都不改动。
#
#   lua 子目录引用（lua_filter@*frost.xxx）已实测可用：
#   librime 的 package.path 含 ~/Library/Rime/lua/?.lua，
#   require 时 frost.xxx 里的点号会被展开成路径分隔符。
#
# 用法：
#   bash install_frost_local.sh              # 安装（默认源 /tmp/rime-frost）
#   FROST_SRC=/path bash install_frost_local.sh
#   bash install_frost_local.sh --uninstall  # 卸载
#
# 装完用 Ctrl+` 打开方案选单，即可在雾凇与白霜之间切换。

set -e

RIME="$HOME/Library/Rime"
SRC="${FROST_SRC:-/tmp/rime-frost}"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
OWNER="$(stat -f '%Su' "$RIME")"

# 白霜引用的 lua 中与雾凇同名但内容不同的，必须隔离
CONFLICTING_LUA=(
    corrector date_translator force_gc is_in_user_dict lunar
    number_translator pin_cand_filter reduce_english_filter
    select_character unicode v_filter
)

# ---------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------
if [ "$1" = "--uninstall" ]; then
    echo "==> 移除白霜文件（雾凇不受影响）"
    rm -f  "$RIME/rime_frost.schema.yaml"
    rm -f  "$RIME/rime_frost.dict.yaml"
    rm -f  "$RIME/rime_frost_aux.schema.yaml"
    rm -f  "$RIME/rime_frost_aux.dict.yaml"
    rm -f  "$RIME/symbols_frost.yaml"
    rm -f  "$RIME/zh-moqi.gram"
    rm -f  "$RIME/rime.lua"
    rm -rf "$RIME/cn_dicts_frost"
    rm -rf "$RIME/cn_dicts_cell"
    rm -rf "$RIME/lua/frost"
    rm -f  "$RIME/build/rime_frost"* 2>/dev/null || true
    rm -f  "$RIME/build/symbols_frost"* 2>/dev/null || true

    echo "==> 从方案列表移除"
    perl -ni -e 'print unless /schema: rime_frost/' "$RIME/default.custom.yaml" 2>/dev/null || true

    echo "==> 重启并部署"
    pkill -x Squirrel 2>/dev/null || true
    sleep 2
    open -a "/Library/Input Methods/Squirrel.app" 2>/dev/null || true
    sleep 3
    "$SQUIRREL" --reload 2>/dev/null || true
    echo "完成，已回到纯雾凇状态（rime_frost.userdb 保留，重装后仍可用）"
    exit 0
fi

# ---------------------------------------------------------------
# 安装
# ---------------------------------------------------------------
[ -d "$SRC" ] || {
    echo "错误：找不到白霜源码 $SRC"
    echo "先执行：git clone --depth 1 https://github.com/gaboolic/rime-frost /tmp/rime-frost"
    exit 1
}
[ -d "$RIME" ] || { echo "错误：找不到 $RIME"; exit 1; }

echo "==> 1/6 方案与词库定义"
cp "$SRC/rime_frost.schema.yaml"     "$RIME/"
cp "$SRC/rime_frost.dict.yaml"       "$RIME/"
# 辅助码方案：主方案的 reverse_lookup 依赖它，缺了会报 table.bin 不存在
cp "$SRC/rime_frost_aux.schema.yaml" "$RIME/"
cp "$SRC/rime_frost_aux.dict.yaml"   "$RIME/"
# 白霜自带的墨奇语法模型，方案里有引用
cp "$SRC/zh-moqi.gram"               "$RIME/"

echo "==> 2/6 词库目录（独立命名，不覆盖雾凇的 cn_dicts）"
rm -rf "$RIME/cn_dicts_frost" "$RIME/cn_dicts_cell"
cp -R "$SRC/cn_dicts"      "$RIME/cn_dicts_frost"
# 细胞词库目录名白霜独有，按原名即可
cp -R "$SRC/cn_dicts_cell" "$RIME/cn_dicts_cell"

echo "==> 3/6 隔离冲突的 lua 到 lua/frost/"
rm -rf "$RIME/lua/frost"
mkdir -p "$RIME/lua/frost"
# 全部复制：非冲突的那几个复制过去也无害，
# 且能避免「白霜更新后某个文件开始有差异」时漏掉
cp "$SRC"/lua/*.lua "$RIME/lua/frost/" 2>/dev/null || true
# 白霜 lua 之间互相 require 时用的是顶层名，放进子目录后要跟着改
for f in "$RIME/lua/frost"/*.lua; do
    [ -f "$f" ] || continue
    perl -pi -e "s/require\s*\(\s*[\"']([a-zA-Z0-9_]+)[\"']\s*\)/require(\"frost.\$1\")/g" "$f"
done

echo "==> 4/6 符号表另存（雾凇用 v 开头键，白霜用 / 开头）"
cp "$SRC/symbols_v.yaml" "$RIME/symbols_frost.yaml"

echo "==> 5/6 改写白霜方案里的引用"
for S in "$RIME/rime_frost.schema.yaml" "$RIME/rime_frost_aux.schema.yaml"; do
    [ -f "$S" ] || continue
    # lua 引用指向 frost 子目录。(?!frost\.) 保证重复执行不会叠成 frost.frost.x
    perl -pi -e 's/lua_(processor|filter|translator)\@\*(?!frost\.)([a-zA-Z0-9_]+)/lua_$1\@*frost.$2/g' "$S"
    # 符号表指向独立副本
    perl -pi -e 's/__include: symbols_v:/__include: symbols_frost:/g' "$S"
done
# 词库路径指向独立目录
perl -pi -e 's/\bcn_dicts\//cn_dicts_frost\//g' "$RIME/rime_frost.dict.yaml"

# rime.lua：librime-lua 对 `*frost.xxx` 这类带点号的引用需要显式声明。
# 不用 pcall 包住——静默失败会让组件被跳过且日志无痕，排查极难。
{
    echo "-- Rime Lua 组件声明（由 install_frost_local.sh 生成）"
    echo "--"
    echo "-- 白霜的 lua 隔离在 lua/frost/ 下，避免与雾凇的同名文件冲突。"
    echo "-- librime-lua 对 \`*frost.xxx\` 这类带点号的引用需要在此声明。"
    echo "-- 雾凇用 lua/ 根目录下的顶层文件，无需声明。"
    echo "--"
    echo "-- 这里故意不用 pcall：加载失败就让它报错，"
    echo "-- 否则组件会被静默跳过、日志里查不到，问题极难定位。"
    echo ""
    echo "frost = {"
    for f in "$RIME/lua/frost"/*.lua; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .lua)
        printf '   %-24s = require("frost.%s"),\n' "$b" "$b"
    done
    echo "}"
} > "$RIME/rime.lua"

echo "==> 6/6 加入方案列表"
D="$RIME/default.custom.yaml"
if ! grep -q "schema: rime_frost" "$D" 2>/dev/null; then
    perl -pi -e 's/^(\s*- schema: rime_ice.*)$/$1\n    - schema: rime_frost   # 白霜拼音（本机试用）/' "$D"
fi

echo "==> 修正权限（脚本可能以 root 跑，属主必须是登录用户）"
chown -R "$OWNER:staff" \
    "$RIME/rime_frost.schema.yaml" "$RIME/rime_frost.dict.yaml" \
    "$RIME/rime_frost_aux.schema.yaml" "$RIME/rime_frost_aux.dict.yaml" \
    "$RIME/symbols_frost.yaml" "$RIME/zh-moqi.gram" "$RIME/rime.lua" \
    "$RIME/cn_dicts_frost" "$RIME/cn_dicts_cell" "$RIME/lua/frost" \
    "$D" 2>/dev/null || true

echo "==> 清理旧产物并重新部署"
rm -f "$RIME/build/rime_frost"* "$RIME/build/symbols_frost"* 2>/dev/null || true
pkill -x Squirrel 2>/dev/null || true
sleep 2
# pkill 后引擎不会自动回来，必须显式拉起，否则 --reload 对空进程执行
open -a "/Library/Input Methods/Squirrel.app" 2>/dev/null || true
sleep 3
"$SQUIRREL" --reload 2>/dev/null || true

echo
echo "完成。词库编译约需 1 分钟，之后："
echo "  按 Ctrl+\` 打开方案选单，选「白霜拼音」"
echo "  同样方式可切回雾凇"
echo
echo "白霜与雾凇的触发词差异："
echo "  符号    雾凇 vfh    白霜 /fh"
echo "  计算器  雾凇 cC1+1  白霜 V1+1"
echo "  日期时间 rq sj xq、拆字 uU、金额 R  两者相同"
echo
echo "卸载：bash install_frost_local.sh --uninstall"
