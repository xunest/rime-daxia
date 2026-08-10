#!/bin/bash
# 把白霜重新加回方案列表。
#
# 什么时候需要跑这个：
#   App 里点「恢复默认」会覆盖 default.custom.yaml，
#   白霜那一行就没了，Ctrl+` 的选单里看不到它。
#   词库、lua、方案文件都还在，只是列表少了一行，跑一下就回来。
#
# 用法：bash readd_frost.sh

set -e
RIME="$HOME/Library/Rime"
D="$RIME/default.custom.yaml"
SQUIRREL="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"

[ -f "$RIME/rime_frost.schema.yaml" ] || {
    echo "错误：白霜没装。先跑 install_frost_local.sh"
    exit 1
}

if grep -q "schema: rime_frost" "$D" 2>/dev/null; then
    echo "白霜已在方案列表里，无需处理"
    exit 0
fi

echo "==> 加回方案列表"
perl -pi -e 's/^(\s*- schema: rime_ice.*)$/$1\n    - schema: rime_frost   # 白霜拼音（本机试用）/' "$D"

echo "==> 重新部署"
pkill -x Squirrel 2>/dev/null || true
sleep 2
# pkill 后引擎不会自动回来，必须显式拉起
open -a "/Library/Input Methods/Squirrel.app" 2>/dev/null || true
sleep 3
"$SQUIRREL" --reload 2>/dev/null || true

echo "完成，Ctrl+\` 里又能看到白霜了"
