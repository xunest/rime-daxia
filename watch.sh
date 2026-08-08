#!/bin/bash
# 改代码自动重新打包
#
# 用法：
#   bash watch.sh          监听 Sources/ 变化，改完存盘就自动构建
#   bash watch.sh --test   只跑自测（更快，适合频繁改逻辑时）
#
# 停止：Ctrl-C
#
# 原理是轮询源码目录的最新修改时间，变了就触发一次构建。
# 用轮询而不是 fswatch，省得你另外装工具。

set -e
cd "$(dirname "$0")"

MODE="build"
if [ "$1" = "--test" ]; then
    MODE="test"
fi

# 源码指纹：任一文件被改动，这个值就会变
fingerprint() {
    find Sources Info.plist -type f \( -name "*.swift" -o -name "*.plist" \
        -o -name "*.yaml" -o -name "*.png" \) -exec stat -f "%m" {} \; \
        2>/dev/null | sort -rn | head -1
}

run_once() {
    local started
    started=$(date '+%H:%M:%S')
    echo ""
    echo "───────────────────────────────────────"
    echo "  $started  检测到改动，开始构建"
    echo "───────────────────────────────────────"

    if [ "$MODE" = "test" ]; then
        if bash build.sh test 2>&1 | grep -E "FAIL|全部通过"; then
            :
        fi
    else
        # 载荷已存在时 release.sh 会自动复用，不会重压词库
        if bash release.sh 2>&1 | grep -vE "^  PASS" | tail -12; then
            :
        fi
    fi

    echo ""
    echo "  等待下一次改动…（Ctrl-C 停止）"
}

echo "监听中：Sources/ 与 Info.plist"
echo "模式：$([ "$MODE" = test ] && echo '只跑自测' || echo '完整构建')"
echo "改完文件存盘即可，Ctrl-C 停止。"

LAST="$(fingerprint)"
run_once

while true; do
    sleep 2
    NOW="$(fingerprint)"
    if [ "$NOW" != "$LAST" ]; then
        LAST="$NOW"
        # 稍等一下，避免编辑器还在写入就触发
        sleep 1
        LAST="$(fingerprint)"
        run_once
    fi
done
