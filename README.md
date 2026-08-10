# 大侠输入法

macOS 上的图形化 Rime 配置工具，内置雾凇拼音词库，一次安装即可使用。

不是新的输入法引擎，而是把 `~/Library/Rime/*.custom.yaml` 的手写 YAML
变成可视化界面，省去查文档改配置的过程。

## 安装

从 [Releases](../../releases) 下载 `大侠输入法.zip`，解压后双击，
点「开始安装」并输入密码。

首次打开若被系统拦截，右键点图标选「打开」，或执行：

```bash
xattr -cr 大侠输入法.app
```

安装器只补缺失文件，已在用 Rime 的话，你的词库与设置不会被覆盖。

## 使用手册

装完先看 **[使用手册](使用手册.md)**。里面是雾凇拼音自带、但界面上看不到的那些能力，每项都带例子：

- 快捷键：中英标点 `Ctrl+Shift+3`、简繁 `Ctrl+Shift+4`、删整个音节 `Ctrl+BackSpace`、以词定字 `[` `]`
- 快捷输入：`rq` 出日期、`sj` 出时间、`nl` 出农历、`uuid` 生成 UUID
- 算式与数字：`cC1+2*3` 算出 7、`R1234` 转金额大写
- 符号库：`vdn` 出 ⌘⌥⇧、`vsx` 出数学符号，`vhelp` 列出全部 70 类
- 生僻字：`uU` + 拼音按音反查，`U` + 码位直接出字
- 自定义短语：打 `yx` 直接出邮箱，权重最高恒排第一

## 功能

- 皮肤：47 套内置配色，支持自定义取色
- 排版：候选横排竖排、字号、圆角、透明度
- 输入：候选数量、模糊音、Shift 切换中英文
- 常用语：自定义短语的可视化编辑
- 实时预览：改动即时反映在候选窗预览里

## 从源码构建

```bash
bash release.sh          # 出 .app
bash release.sh --zip    # 额外出可分享的 zip
bash build.sh test       # 只跑自测
bash watch.sh --test     # 改代码自动跑自测
```

引擎与词库不在仓库里（语法模型 400M，超出 GitHub 限制）。
本机已装鼠须管并克隆过雾凇时，`release.sh` 会自动找到它们；
否则先执行：

```bash
bash fetch_sources.sh /tmp/sources
SQUIRREL_SRC=/tmp/sources/Squirrel.app RIME_SRC=/tmp/sources/rime bash make_payload.sh
```

## 致谢与许可

本项目基于以下开源项目：

- [RIME 鼠须管](https://github.com/rime/squirrel)（GPL-3.0）——输入法引擎
- [雾凇拼音](https://github.com/iDvel/rime-ice)（LGPL-3.0）——词库与方案
- [万象语法模型](https://github.com/amzxyz/RIME-LMDG)——语法模型

内置引擎是鼠须管的修改版（替换了显示名称与图标），依 GPL-3.0 要求，
修改部分已在此声明。配置界面部分代码见本仓库。
