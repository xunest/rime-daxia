#!/bin/bash
# 从网络获取构建载荷所需的原料
#
# 与 make_payload.sh 的分工：
#   本脚本   负责「从哪儿弄到引擎和词库」——下载并摆放到位
#   make_payload.sh  负责「把它们加工成载荷」——品牌化、脱敏、压缩
#
# 本地构建时用不上它：本机已装鼠须管、已克隆雾凇，release.sh 会直接复用。
# 它是给 CI 用的——GitHub 的构建机是干净的，什么都没有。
#
# 用法：bash fetch_sources.sh <目标目录>
#   产出 <目标目录>/Squirrel.app 与 <目标目录>/rime（git 克隆）

set -e

DEST="${1:?用法: bash fetch_sources.sh <目标目录>}"
mkdir -p "$DEST"

GRAM_URL="https://cnb.cool/Mintimate/rime/oh-my-rime/-/releases/download/latest/wanxiang-lts-zh-hans.gram"
RIME_ICE_REPO="https://github.com/iDvel/rime-ice.git"

# ---------------------------------------------------------------
echo "==> 获取鼠须管引擎"
# 官方只发 .pkg，里面才是 Squirrel.app。用 pkgutil 展开而不是
# installer，因为 CI 里不该真去安装输入法，只要取出 app。
SQ_TAG=$(curl -fsSL "https://api.github.com/repos/rime/squirrel/releases/latest" \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$SQ_TAG" ] || { echo "错误：取不到鼠须管版本号"; exit 1; }
echo "    版本 $SQ_TAG"

PKG="$DEST/squirrel.pkg"
curl -fsSL -o "$PKG" \
    "https://github.com/rime/squirrel/releases/download/$SQ_TAG/Squirrel-$SQ_TAG.pkg"

EXPAND="$DEST/.pkg_expand"
rm -rf "$EXPAND"
pkgutil --expand-full "$PKG" "$EXPAND"

# pkg 内部结构可能随版本变化，直接搜出 Squirrel.app
APP_SRC=$(find "$EXPAND" -maxdepth 4 -name "Squirrel.app" -type d | head -1)
[ -n "$APP_SRC" ] || { echo "错误：pkg 里找不到 Squirrel.app"; exit 1; }

rm -rf "$DEST/Squirrel.app"
# 用 ditto 保住签名所需的扩展属性，cp -R 会丢
ditto "$APP_SRC" "$DEST/Squirrel.app"
rm -rf "$EXPAND" "$PKG"
echo "    已就位：$(du -sh "$DEST/Squirrel.app" | cut -f1)"

# ---------------------------------------------------------------
echo "==> 克隆雾凇拼音"
# 必须是 git 克隆：make_payload.sh 靠 git archive HEAD 保证
# 只导出官方提交里的文件，这是隔离个人数据的关键机制。
# 用 --depth 1 省时间，git archive 不需要完整历史。
RIME_DIR="$DEST/rime"
rm -rf "$RIME_DIR"
git clone --depth 1 --quiet "$RIME_ICE_REPO" "$RIME_DIR"
echo "    版本 $(git -C "$RIME_DIR" rev-parse --short HEAD)"

# ---------------------------------------------------------------
echo "==> 下载万象语法模型"
# 400M 左右，是整个包里最大的单个文件。
# 它不在 rime-ice 仓库里，得单独取。
GRAM="$RIME_DIR/wanxiang-lts-zh-hans.gram"
curl -fSL --retry 3 --retry-delay 5 -o "$GRAM" "$GRAM_URL"

# 校验：下载失败时服务端可能返回一个 HTML 错误页，
# 体积对不上就直接失败，避免把坏文件打进包里
GRAM_SIZE=$(stat -f%z "$GRAM" 2>/dev/null || stat -c%s "$GRAM")
if [ "$GRAM_SIZE" -lt 100000000 ]; then
    echo "错误：语法模型只有 $GRAM_SIZE 字节，明显不对"
    exit 1
fi
echo "    已下载：$(du -h "$GRAM" | cut -f1)"

# ---------------------------------------------------------------
# 我们自己新增的文件，从项目里带过去
echo "==> 补入自有文件"
SELF="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$RIME_DIR/lua"
for f in lua/shift_toggle.lua predict-zhs.db; do
    if [ -f "$SELF/extras/$f" ]; then
        cp "$SELF/extras/$f" "$RIME_DIR/$f"
        echo "    $f"
    else
        echo "    跳过 $f（extras/ 里没有）"
    fi
done

echo ""
echo "原料就绪："
echo "  引擎：$DEST/Squirrel.app"
echo "  词库：$RIME_DIR"
