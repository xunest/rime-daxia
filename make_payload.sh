#!/bin/bash
# 生成分发用的安装载荷（payload）
#
# 设计原则：白名单而非黑名单
#   Rime 配置用 `git archive HEAD` 从 rime-ice 官方仓库导出原版文件，
#   再单独补上我们自己新增的少数文件。个人数据（词频记忆、安装 ID、
#   本机编译产物、自己改过的常用语）从原理上就进不了包，
#   不依赖「记得排除某个文件」这种容易漏的黑名单。
#
# 用法：bash make_payload.sh

set -e
cd "$(dirname "$0")"

# 雾凇配置的来源，须是 rime-ice 的 git 克隆。
# 默认取当前用户的配置目录；本机已改动或已搬走时，
# 可用 RIME_SRC 指向任意一份克隆，例如备份目录。
#
# 引擎默认取系统已安装的鼠须管；本机已卸载时可用
# SQUIRREL_SRC 指向备份的 Squirrel.app。
RIME_DIR="${RIME_SRC:-$HOME/Library/Rime}"
SQUIRREL_APP="${SQUIRREL_SRC:-/Library/Input Methods/Squirrel.app}"
OUT_DIR="payload"
ICON_PNG="Sources/RimeKit/Resources/AppIcon.png"
ICON_ICNS=".build_manual/AppIcon.icns"
BUILD_DIR=".build_manual"
EXEC_NAME="DaxiaIME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 我们在官方 rime-ice 之外新增的文件，需要一并分发
EXTRA_FILES=(
    "lua/shift_toggle.lua"          # Shift 切换中英文
    "predict-zhs.db"                # 输入预测库
    "wanxiang-lts-zh-hans.gram"     # 万象语法模型
)

# 绝不允许出现在 payload 里的个人数据，构建末尾会逐项体检
#
# 分两类检查，避免误伤官方仓库自带的同名文件：
#   ROOT_FORBIDDEN  只查 Rime 根目录。个人配置与词典只可能在根目录，
#                   而 others/iRime/ 等示例目录里有同名模板文件属正常内容。
#   ANY_FORBIDDEN   全目录递归查，这些特征文件在任何位置都不该出现。
#
# build/ 不在此列：rime-ice 官方仓库本身含 build/.gitkeep 占位，与本机
# 编译产物同名。git archive 只导出受版本控制的占位文件，本机那些
# .bin 编译产物不受版本控制，天然进不了包。
ROOT_FORBIDDEN=(
    "installation.yaml"     # 含 installation_id 机器指纹
    "user.yaml"             # 使用统计
    "squirrel.custom.yaml"  # 本机界面配置，装机后由 App 生成
    "default.custom.yaml"
    "rime_ice.custom.yaml"
)
ANY_FORBIDDEN=(
    "*.userdb"              # 打字记忆：累积的真实词频
    "*.userdb.txt"
    "*.table.bin"           # 词库编译产物
    "*.prism.bin"
    "*.reverse.bin"
    ".git"
)

echo "==> 检查环境"
[ -d "$RIME_DIR/.git" ] || { echo "错误：$RIME_DIR 不是 git 仓库，无法保证导出干净"; exit 1; }
[ -d "$SQUIRREL_APP" ] || { echo "错误：未找到 $SQUIRREL_APP"; exit 1; }
[ -f "$ICON_PNG" ] || { echo "错误：未找到图标源 $ICON_PNG"; exit 1; }
# .icns 与可执行文件都由 build.sh 生成，用来导出矢量菜单栏图标
if [ ! -f "$ICON_ICNS" ] || [ ! -x "$BUILD_DIR/$EXEC_NAME" ]; then
    echo "错误：请先运行 bash build.sh 生成图标与可执行文件"
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------
# 1. 鼠须管引擎
# ---------------------------------------------------------------
# 必须用 ditto 复制（保留扩展属性与符号链接），否则官方签名失效。
# SharedSupport 下的 build/、installation.yaml、user.yaml 是运行时
# 产生的，既污染签名也含本机数据，复制后立即删除。
echo "==> 打包鼠须管引擎（官方原版）"
ditto "$SQUIRREL_APP" "$WORK/Squirrel.app"
rm -rf "$WORK/Squirrel.app/Contents/SharedSupport/build"
rm -f  "$WORK/Squirrel.app/Contents/SharedSupport/installation.yaml"
rm -f  "$WORK/Squirrel.app/Contents/SharedSupport/user.yaml"

if ! codesign --verify --deep --strict "$WORK/Squirrel.app" 2>/dev/null; then
    echo "错误：清理后鼠须管签名仍无效，装到别人机器上会被系统拒绝"
    exit 1
fi
echo "    官方签名完好"

ditto -c -k --sequesterRsrc --keepParent "$WORK/Squirrel.app" "$OUT_DIR/Squirrel.zip"

# ---------------------------------------------------------------
# 1b. 品牌化引擎：菜单栏与系统设置里显示「大侠输入法」
# ---------------------------------------------------------------
# 系统输入法菜单的名字来自各语言 .lproj/InfoPlist.strings，不是 Info.plist。
# 输入法自己那个菜单（点菜单栏图标弹出的）另有来源：
# Localizable.strings 里的 "Squirrel" = "鼠须管"，两处都要改。
#
# Bundle ID 与 Swift 模块名不能改：Info.plist 的
# InputMethodServerControllerClass 是 Squirrel.SquirrelInputController，
# 那个 Squirrel. 前缀已编译进二进制，改了 InputMethodKit 就找不到控制器类。
# Bundle ID 用户基本看不到，保持原值。
#
# 改动任何字节都会让官方签名失效，必须重签。adhoc 签名的输入法在部分
# 机器上可能被系统拒绝加载，因此上面的官方原版一并保留作为回退。
echo "==> 打包品牌化引擎（大侠输入法）"
ditto "$WORK/Squirrel.app" "$WORK/DaxiaIME.app"

for lproj in zh-Hans zh-Hant en; do
    for name in InfoPlist Localizable; do
        f="$WORK/DaxiaIME.app/Contents/Resources/$lproj.lproj/$name.strings"
        [ -f "$f" ] || continue
        # 只替换 <string> 里的值。Localizable.strings 的键名就是
        # "Squirrel"，代码按键查表，改了键会让菜单项显示不出来。
        plutil -convert xml1 "$f" -o - \
            | sed -e 's/鼠须管/大侠输入法/g' \
                  -e 's/鼠鬚管/大侠输入法/g' \
                  -e 's|<string>Squirrel</string>|<string>Daxia IME</string>|g' \
                  -e 's|<string>Squirrel - Simplified</string>|<string>Daxia IME</string>|g' \
                  -e 's|<string>Squirrel - Traditional</string>|<string>Daxia IME (Traditional)</string>|g' \
                  -e 's/Squirrel is ready/Daxia IME is ready/g' \
                  -e 's/式恕堂 版权所无/基于 RIME 鼠须管（GPL-3.0）修改/g' \
                  -e 's/Copyleft, RIME Developers/Modified from RIME Squirrel (GPL-3.0)/g' \
            | plutil -convert binary1 - -o "$f"
    done
done
echo "    显示名已改为大侠输入法"

# App 图标：文件名必须保持 Rime.icns，Info.plist 的 CFBundleIconFile 指向它
cp "$ICON_ICNS" "$WORK/DaxiaIME.app/Contents/Resources/Rime.icns"

# 菜单栏与系统设置列表用的图标：必须是纯矢量 PDF。
# 用 sips 从 PNG 转出的 PDF 内嵌位图，系统会按原始像素渲染，
# 把设置里的输入法列表行高撑到极大且看不到内容。
"./$BUILD_DIR/$EXEC_NAME" --export-menubar-pdf "$WORK/menubar.pdf"
cp "$WORK/menubar.pdf" "$WORK/DaxiaIME.app/Contents/Resources/rime.pdf"
echo "    图标已替换"

codesign --force --deep -s - "$WORK/DaxiaIME.app" 2>/dev/null
if ! codesign --verify --deep --strict "$WORK/DaxiaIME.app" 2>/dev/null; then
    echo "错误：品牌化引擎重签名失败"
    exit 1
fi
echo "    已重签名（adhoc）"

ditto -c -k --sequesterRsrc --keepParent "$WORK/DaxiaIME.app" "$OUT_DIR/DaxiaIME.zip"

# ---------------------------------------------------------------
# 2. 雾凇拼音配置
# ---------------------------------------------------------------
echo "==> 打包雾凇拼音配置"
mkdir -p "$WORK/rime"
# git archive 导出的是 HEAD 提交的内容，本机未提交的改动一律不含
( cd "$RIME_DIR" && git --no-optional-locks archive HEAD ) | tar -x -C "$WORK/rime"

REV="$(cd "$RIME_DIR" && git --no-optional-locks rev-parse --short HEAD | tr -d '\r\n')"
printf '    rime-ice 版本 %s，官方原版，不含本机改动\n' "$REV"

for f in "${EXTRA_FILES[@]}"; do
    if [ ! -e "$RIME_DIR/$f" ]; then
        echo "错误：缺少要分发的文件 $f"
        exit 1
    fi
    mkdir -p "$WORK/rime/$(dirname "$f")"
    cp "$RIME_DIR/$f" "$WORK/rime/$f"
    echo "    补入 $f"
done

# ---------------------------------------------------------------
# 3. 体检：确认没有夹带个人数据
# ---------------------------------------------------------------
echo "==> 隐私体检"
for name in "${ROOT_FORBIDDEN[@]}"; do
    if [ -e "$WORK/rime/$name" ]; then
        echo "错误：payload 根目录发现个人数据 $name，已中止"
        exit 1
    fi
done
for name in "${ANY_FORBIDDEN[@]}"; do
    hit="$(find "$WORK/rime" -name "$name" | head -1)"
    if [ -n "$hit" ]; then
        echo "错误：payload 中发现个人数据"
        echo "      规则：$name"
        echo "      文件：$hit"
        exit 1
    fi
done
echo "    未发现个人数据"

tar -czf "$OUT_DIR/rime.tar.gz" -C "$WORK/rime" .

# ---------------------------------------------------------------
echo "==> 记录版本信息"
cat > "$OUT_DIR/payload.txt" <<EOF
rime_ice_rev=$REV
squirrel_version=$(defaults read "$SQUIRREL_APP/Contents/Info.plist" CFBundleVersion)
engine_branded=DaxiaIME.zip
engine_original=Squirrel.zip
built_at=$(date '+%Y-%m-%d %H:%M:%S')
EOF

echo ""
echo "完成："
du -h "$OUT_DIR"/* | sed 's/^/  /'
