#!/bin/bash
# 一条命令出成品
#
# 用法：
#   bash release.sh              增量：载荷已存在就复用，只重编界面
#   bash release.sh --full       完整：连载荷一起重做（换了引擎或词库时用）
#   bash release.sh --zip        额外产出可直接分享的 zip
#
# 与 build.sh 的分工：
#   build.sh       只管编译打包，是本脚本的一环，也可单独用
#   make_payload.sh 只管生成引擎与词库载荷，耗时最久
#   release.sh     串起两者，并自动找到引擎与词库的来源
#
# 解决的问题：
#   1. 载荷来源要手动设 SQUIRREL_SRC / RIME_SRC，本脚本自动探测
#   2. 载荷没变时不必重做，省掉几分钟
#   3. DMG 在受限环境下会失败，改为可选且失败不影响 app

set -e
cd "$(dirname "$0")"

APP_LABEL="大侠输入法"
PAYLOAD_DIR="payload"
DIST_DIR="dist"

FULL=0
MAKE_ZIP=0
for arg in "$@"; do
    case "$arg" in
        --full) FULL=1 ;;
        --zip)  MAKE_ZIP=1 ;;
        *) echo "未知参数：$arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------
# 探测载荷来源
# ---------------------------------------------------------------
# 引擎与词库可能在系统里、也可能在备份里（本机卸载后就只剩备份）。
# 按优先级挨个找，省得每次手动指定环境变量。
find_squirrel() {
    [ -n "$SQUIRREL_SRC" ] && { echo "$SQUIRREL_SRC"; return; }
    local candidates=(
        "/Library/Input Methods/Squirrel.app"
        "$HOME/MyLab/Squirrel-backup-1.1.2.app"
    )
    for c in "${candidates[@]}"; do
        [ -x "$c/Contents/MacOS/Squirrel" ] && { echo "$c"; return; }
    done
    # 退而求其次：找任意一份备份
    ls -d "$HOME"/MyLab/Squirrel-backup*.app 2>/dev/null | head -1
}

find_rime() {
    [ -n "$RIME_SRC" ] && { echo "$RIME_SRC"; return; }
    # 必须是 git 克隆：make_payload.sh 靠 git archive 保证只导出官方文件
    [ -d "$HOME/Library/Rime/.git" ] && { echo "$HOME/Library/Rime"; return; }
    ls -d "$PWD"/Rime-backup-*/ 2>/dev/null | head -1 | sed 's:/$::'
}

# ---------------------------------------------------------------
# 载荷
# ---------------------------------------------------------------
payload_ready() {
    [ -f "$PAYLOAD_DIR/DaxiaIME.zip" ] &&
    [ -f "$PAYLOAD_DIR/Squirrel.zip" ] &&
    [ -f "$PAYLOAD_DIR/rime.tar.gz" ]
}

if [ "$FULL" = 1 ] || ! payload_ready; then
    if payload_ready; then
        echo "==> 重做载荷（--full）"
    else
        echo "==> 载荷缺失，开始生成"
    fi

    SQ="$(find_squirrel)"
    RM="$(find_rime)"

    if [ -z "$SQ" ]; then
        echo "错误：找不到鼠须管引擎"
        echo "      请装一次官方鼠须管，或用 SQUIRREL_SRC 指向备份的 .app"
        exit 1
    fi
    if [ -z "$RM" ]; then
        echo "错误：找不到 rime-ice 的 git 克隆"
        echo "      请用 RIME_SRC 指向一份克隆目录"
        exit 1
    fi
    echo "    引擎：$SQ"
    echo "    词库：$RM"

    SQUIRREL_SRC="$SQ" RIME_SRC="$RM" bash make_payload.sh
else
    echo "==> 复用现有载荷（加 --full 可重做）"
    grep -E "rime_ice_rev|squirrel_version|built_at" \
        "$PAYLOAD_DIR/payload.txt" 2>/dev/null | sed 's/^/    /' || true
fi

# ---------------------------------------------------------------
# 编译打包
# ---------------------------------------------------------------
echo ""
bash build.sh

# ---------------------------------------------------------------
# 分享用的压缩包
# ---------------------------------------------------------------
APP="$DIST_DIR/$APP_LABEL.app"
if [ "$MAKE_ZIP" = 1 ]; then
    echo ""
    echo "==> 打包 zip"
    ZIP="$APP_LABEL.zip"
    rm -f "$ZIP"
    # ditto -k 才能保住签名与符号链接，用 zip 命令会破坏 bundle
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "    $(du -h "$ZIP" | cut -f1)  $ZIP"
fi

# ---------------------------------------------------------------
echo ""
echo "=== 产物 ==="
echo "  $(du -sh "$APP" | cut -f1)  $APP"
if [ -f "$APP_LABEL.zip" ]; then
    echo "  $(du -h "$APP_LABEL.zip" | cut -f1)  $APP_LABEL.zip"
fi
echo ""
echo "架构：$(lipo -archs "$APP/Contents/MacOS/DaxiaIME")"
codesign --verify --deep --strict "$APP" 2>/dev/null \
    && echo "签名：有效" || echo "签名：校验未通过"
