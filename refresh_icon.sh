#!/bin/bash
# 强制刷新输入法图标缓存
#
# 用法：bash refresh_icon.sh
#
# 换了菜单栏图标（Contents/Resources/rime.pdf）后，系统常常还显示旧图。
# 原因是图标被多层缓存住了，光重启引擎进程没用：
#
#   LaunchServices  记住了 bundle 的图标与显示名
#   iconservicesd   维护渲染好的图标位图缓存
#   TextInputMenuAgent  菜单栏那个输入法菜单的宿主进程，图标读一次就留着
#
# 所以要逐层清掉再让它们重建。脚本只碰缓存与这几个进程，
# 不改配置、不动词库，随时可以重复跑。

set -e
cd "$(dirname "$0")"

ENGINE="/Library/Input Methods/Squirrel.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$ENGINE" ]; then
    echo "错误：未找到输入法引擎 $ENGINE"
    echo "      请先安装大侠输入法。"
    exit 1
fi

echo "==> 当前图标文件"
ls -l "$ENGINE/Contents/Resources/rime.pdf" | sed 's/^/    /'

echo "==> 重新登记 bundle（LaunchServices）"
# -f 强制重读该 bundle 的 Info.plist 与图标资源
"$LSREGISTER" -f "$ENGINE" 2>/dev/null || true
# 修改时间变一下，能让部分缓存判定为已过期
touch "$ENGINE" 2>/dev/null || true

echo "==> 清理图标位图缓存（iconservicesd）"
# 这两个缓存目录属于当前用户，无需提权
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.IconServices" 2>/dev/null || true
# iconservicesd 以 _iconservices 身份运行，普通用户杀不掉，需要提权。
# 但它对输入法菜单栏图标影响不大，杀不掉就跳过，不为它卡住脚本。
if killall iconservicesd 2>/dev/null; then
    echo "    已重启 iconservicesd"
else
    echo "    跳过 iconservicesd（需管理员权限，通常不影响输入法图标）"
fi

echo "==> 重启输入法引擎"
# 引擎也由 launchd 托管，杀掉后会被重新拉起
killall -9 Squirrel 2>/dev/null || true
sleep 1

echo "==> 重启输入法菜单（TextInputMenuAgent）"
# 菜单栏那一栏由它绘制，图标读一次就缓存住了，必须重启才会重读
killall TextInputMenuAgent 2>/dev/null || true
# 通知系统输入源列表有变化，菜单据此重建
sleep 1

echo "==> 拉起引擎"
open -a "$ENGINE" 2>/dev/null || true
sleep 2

if pgrep -x Squirrel >/dev/null; then
    echo "    引擎已运行"
else
    echo "    引擎尚未就绪，切换一次输入法即可唤起"
fi

echo ""
echo "完成。"
echo ""
echo "菜单栏若还是旧图标，按顺序试："
echo "  1. 用 Ctrl-Space 切到别的输入法再切回来"
echo "  2. 到「系统设置 → 键盘 → 输入法」把大侠输入法移除后重新添加"
echo "  3. 注销当前用户重新登录（对图标缓存最彻底）"
