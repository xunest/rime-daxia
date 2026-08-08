#!/bin/bash
# 大侠输入法 构建脚本
# 用法：bash build.sh        编译 + 生成图标 + 打包 .app
#      bash build.sh test   只跑自测
#      bash build.sh dmg    额外生成 DMG
#
# 想分发给没装过鼠须管的机器，先运行 bash make_payload.sh 生成
# 内嵌载荷（引擎 + 词库），本脚本会自动把它打进 .app。
# 或者直接用 bash release.sh，它会自动串起这两步。

set -e
cd "$(dirname "$0")"

APP_LABEL="大侠输入法"        # 显示名称
EXEC_NAME="DaxiaIME"          # 可执行文件名，须与 Info.plist 一致
BUILD_DIR=".build_manual"
DIST_DIR="dist"
STAGE_DIR="dmg_stage"
PAYLOAD_DIR="payload"
ICONSET="$BUILD_DIR/AppIcon.iconset"

echo "==> 编译（universal）"
mkdir -p "$BUILD_DIR"
# 分架构编译再 lipo 合并，Intel 与 Apple 芯片的 Mac 都能运行。
# swiftc 不支持一次传两个 -target，只能各编一次。
for arch in arm64 x86_64; do
    echo "    $arch"
    swiftc -target "$arch-apple-macos13" -O -parse-as-library \
        Sources/RimeKit/*.swift -o "$BUILD_DIR/$EXEC_NAME.$arch"
done
lipo -create -output "$BUILD_DIR/$EXEC_NAME" \
    "$BUILD_DIR/$EXEC_NAME.arm64" "$BUILD_DIR/$EXEC_NAME.x86_64"
rm -f "$BUILD_DIR/$EXEC_NAME.arm64" "$BUILD_DIR/$EXEC_NAME.x86_64"
echo "    合并完成：$(lipo -archs "$BUILD_DIR/$EXEC_NAME")"

# 图标原图放到可执行文件同级，供 --export-icons 读取
cp Sources/RimeKit/Resources/AppIcon.png "$BUILD_DIR/AppIcon.png"

echo "==> 自测"
"./$BUILD_DIR/$EXEC_NAME" --selftest

if [ "$1" = "test" ]; then
    exit 0
fi

echo "==> 生成图标"
rm -rf "$ICONSET"
"./$BUILD_DIR/$EXEC_NAME" --export-icons "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

echo "==> 打包 .app"
APP_BUNDLE="$DIST_DIR/$APP_LABEL.app"
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$EXEC_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp Sources/RimeKit/Resources/AppIcon.png "$APP_BUNDLE/Contents/Resources/"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# 内嵌安装载荷，使 app 在没装过鼠须管的机器上也能自行安装。
# payload 由 make_payload.sh 生成；缺失时给出提示但不中断，
# 便于只想编界面时快速构建。
if [ -d "$PAYLOAD_DIR" ]; then
    echo "==> 内嵌安装载荷"
    # 用 ditto 保留 zip 内的签名相关属性
    ditto "$PAYLOAD_DIR" "$APP_BUNDLE/Contents/Resources/payload"
    du -sh "$APP_BUNDLE/Contents/Resources/payload" | sed 's/^/    /'
else
    echo "==> 跳过安装载荷（未找到 $PAYLOAD_DIR）"
    echo "    先运行 bash make_payload.sh 才能分发给未装鼠须管的机器"
fi

echo "==> 签名（adhoc）"
# payload 里的 zip 是数据文件，不参与签名验证；
# --deep 会遍历整个 bundle，载荷大时较慢但必要
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> 刷新系统图标缓存"
# 让程序坞、Finder、启动台立即读到新图标与名称
touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" 2>/dev/null || true

# DMG 只在明确要求时生成。分享单个 .app 或 zip 更常用，
# 而且 hdiutil 需要挂载磁盘设备，在受限环境里会失败。
if [ "$1" = "dmg" ]; then
    echo "==> 生成 DMG"
    rm -rf "$STAGE_DIR" "$APP_LABEL.dmg"
    mkdir -p "$STAGE_DIR"
    # 用 ditto 而非 cp -R，保留签名所需的扩展属性
    ditto "$APP_BUNDLE" "$STAGE_DIR/$APP_LABEL.app"
    ln -s /Applications "$STAGE_DIR/Applications"
    hdiutil create -volname "$APP_LABEL" -srcfolder "$STAGE_DIR" \
        -ov -format UDZO "$APP_LABEL.dmg"
    rm -rf "$STAGE_DIR"
fi

echo ""
echo "完成："
echo "  App: $(pwd)/$APP_BUNDLE"
if [ -f "$APP_LABEL.dmg" ]; then
    echo "  DMG: $(pwd)/$APP_LABEL.dmg"
fi
echo ""
echo "如果程序坞图标未更新，把旧图标从程序坞移除后重新拖入。"
