# 开发笔记

自用备忘，记录踩过的坑与设计取舍。用户文档见 README。

## 构建

```bash
bash release.sh          # 日常，复用载荷，约 30 秒
bash release.sh --full   # 换了引擎或词库时才用，要重压 385M
bash release.sh --zip    # 额外出 zip
bash watch.sh --test     # 改代码自动跑自测
bash build.sh dmg        # 需要 DMG 时
```

`release.sh` 会自动探测引擎与词库来源：先找系统里已装的鼠须管与
`~/Library/Rime`，找不到就退到 `~/MyLab/` 下的备份。所以本机卸载了
输入法也能继续打包。

## CI 的两条流程

| 文件 | 触发 | 内容 | 耗时 | 实际额度 |
|------|------|------|------|----------|
| `ci.yml` | 推 main、提 PR | 编译 + 自测 | 约 30 秒 | ~5 分钟 |
| `release.yml` | 推 `v*` tag | 完整打包 + 发 Release | 约 20 分钟 | ~200 分钟 |

**为什么拆开**：macOS runner 按 10 倍计费，免费额度 2000 分钟/月。
完整打包一次扣 200 分钟，若每次推送都跑，推十次就用光。

发版：

```bash
# 先改 Info.plist 里的 CFBundleShortVersionString 与 CFBundleVersion
git tag v0.2 && git push origin v0.2
```

发版前想试装：Actions 页面手动触发「发布」——只产出 Artifacts，
不会创建 Release。

## 踩过的坑

### 输入源启用

`TISEnableInputSource` 会**静默失效**：返回 noErr、属性查询显示
`enabled=true`，但并没有写进偏好里的 `AppleEnabledInputSources`。
菜单栏读的正是那个数组，于是列表里始终看不到。

解法是直接写偏好数组，条目结构与手动在系统设置里添加时一致：

```
Bundle ID       im.rime.inputmethod.Squirrel        ← 父级
Input Mode      im.rime.inputmethod.Squirrel.Hans   ← 带后缀
InputSourceKind Input Mode
```

两个附带教训：

- 输入源 ID 必须带 `.Hans`。不带后缀的父级 bundle
  `IsSelectCapable` 为 false，选它不生效。
- 查系统偏好**不能用 `defaults read`**，它读 cfprefsd 的内存缓存，
  会给出过期结果。用 `plutil -p` 直读文件或 CFPreferences API。

### TIS 必须在主线程

`TISCreateInputSourceList` 等函数内部有 `dispatch_assert_queue`
断言，在后台队列调用直接 SIGTRAP 崩溃，不是返回错误码。

### 引擎进程由 launchd 托管

杀掉后会被立刻拉起。所以替换引擎时要**杀两次**：先杀一次腾出文件，
`ditto` 完再杀一次——第二次清掉的是替换期间被 launchd 拉起、
仍持有旧文件的进程。少了第二次，状态栏会一直挂着旧版图标和名字。

`Squirrel --quit` 对这类进程无效，只能用 `pkill -9`。

### 品牌名有两处来源

改显示名要同时改两个文件，漏一个就会在某处露出「鼠须管」：

| 文件 | 影响 |
|------|------|
| `InfoPlist.strings` | 系统设置里的输入法列表 |
| `Localizable.strings` | 输入法自己的菜单（点状态栏图标弹出的） |

`Localizable.strings` 里键名就是 `Squirrel`，**键不能改**，代码按键
查表，改了菜单项会显示不出来。只替换 `<string>` 值节点。

### 菜单栏图标必须是纯矢量 PDF

用 `sips` 从 PNG 转出的 PDF 内嵌位图，系统按原始像素渲染，会把
系统设置里的输入法列表行高撑到极大。改用 Core Graphics 直接绘制
矢量路径（`AppIcon.exportMenuBarPDF`）。

### 自测不能依赖本机环境

楷体、行楷属于 macOS 的「附加字体」，需用户手动下载。CI 的构建机
没有它们，导致 4 项字体分类自测必然失败。改为只在检测到字体时才校验。

同类问题还有一次：`make_payload.sh` 需要 `.icns` 与可执行文件，
但 workflow 里跑的是 `build.sh test`——它自测完就退出，从没走到
生成图标那步。

### CI 调 GitHub API 要认证

匿名请求限流 60 次/小时/IP，runner 出口 IP 共享，额度通常早被占满，
直接 403。带上 `secrets.GITHUB_TOKEN` 后升到 5000 次。

## 隐私设计

`make_payload.sh` 用 `git archive HEAD` 从 rime-ice 仓库导出，
再单独补上我们新增的少数文件。这是**白名单而非黑名单**——个人数据
（词频记忆 userdb、安装 ID、本机编译产物、自改的常用语）从原理上
就进不了包，不依赖「记得排除某个文件」这种容易漏的做法。

构建末尾还有一道隐私体检，逐项检查禁止出现的文件名。

## 已知限制

**adhoc 签名**。用户首次打开需右键选「打开」或 `xattr -cr`。
正规做法是 Apple Developer 证书（$99/年）+ notarytool 公证。

输入法比普通 app 更敏感，adhoc 签名的输入法在某些机器上可能直接
不被系统加载——这也是保留「改用官方原版引擎」那个回退按钮的原因。

**验证覆盖有限**。目前只在一台 Apple Silicon、macOS 13 上装过。
Intel 机器与其他系统版本未验证，所以版本号定为 0.1。
