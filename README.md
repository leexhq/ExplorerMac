# ExplorerMac 资源管理器

一个接近 Windows 11 文件资源管理器布局的 macOS 原生应用。界面为中文，使用 Swift、AppKit、SwiftUI、Image I/O 和系统 Quick Look；无需安装 Python、Node.js 或其他运行环境。

[![Build and test](https://github.com/leexhq/ExplorerMac/actions/workflows/ci.yml/badge.svg)](https://github.com/leexhq/ExplorerMac/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 本项目是独立开发的软件，与 Microsoft 或 Apple 无隶属关系。

## 直接运行

从 [Releases](https://github.com/leexhq/ExplorerMac/releases/latest) 下载 `ExplorerMac-macOS-Universal.zip`，解压后双击 **ExplorerMac.app**。也可以将它拖入“应用程序”文件夹，再固定到 Dock。

- 系统要求：macOS 14 Sonoma 或更高。
- 通用二进制：同时包含 Apple Silicon（arm64）和 Intel（x86_64）。
- 已在本机 Apple Silicon / macOS 26.6.2 上启动与操作验证。Intel 版本已交叉编译，未在 Intel 实机测试。
- Release 中的 `ExplorerMac-macOS-Universal.zip` 是应用的便携压缩包。
- 应用本身不上传文件，不包含登录、广告、遥测或自动更新。

这是本地构建并进行 ad hoc 签名的版本，尚未使用 Developer ID 签名或通过 Apple 公证。在这台 Mac 上已成功启动；通过互联网传到另一台 Mac 时，首次运行可能出现开发者验证提示。若你确认信任此源码和构建，可按 [Apple 的说明](https://support.apple.com/en-gb/102445) 在“系统设置 → 隐私与安全”中对这个应用选择“仍要打开”。不需要关闭系统整体安全保护。

访问桌面、文稿、下载或外置磁盘时，macOS 可能弹出对应的文件访问授权。无法读取目录时，可以使用“打开其他位置…”重新选择目录；应用不会自动申请完全磁盘访问权限。

## 已实现的功能

| 类别 | 功能 |
| --- | --- |
| Windows 风格布局 | 标签页、命令栏、面包屑地址、搜索、快速访问、黄色文件夹、状态栏、右侧预览 |
| 导航 | 前进、后退、上一级、直接输入路径、`~` 主目录、打开目录对话框、多窗口 |
| 标签页 | 新建、关闭、切换，退出后恢复打开的文件夹 |
| 左侧导航 | 常用目录、自定义固定、磁盘、按需展开的目录树、应用内最近访问 |
| 文件显示 | 详细信息、中等图标、大图标、超大图标；名称、日期、类型、大小排序；文件夹优先 |
| 图片 | 真实 PNG/JPEG 等格式缩略图、方向信息处理、异步加载、内存缓存、右侧图片预览 |
| 大预览 | 空格打开、左右键切换、图片适应窗口/100%/放大缩小/触控板缩放 |
| 文档预览 | PDF、文本及系统支持的文档/音视频，通过 Quick Look 显示 |
| 选择 | 单选、多选、Shift 范围选择、⌘ 全选、原生网格与表格键盘导航 |
| 文件操作 | 新建文件夹/文本、复制、剪切、粘贴、复制到/移动到、重命名、废纸篓删除 |
| 撤销 | 当前运行期间最近 30 次文件操作，可撤销移动、重命名、新建、复制、压缩及可恢复的废纸篓操作 |
| 拖放 | 网格、列表、快速访问支持拖入复制，也可拖出到其他应用 |
| ZIP | 右键单个/多个项目压缩为 ZIP；双击已有 ZIP 使用系统默认应用解压 |
| 搜索 | 按文件/文件夹名称搜索，可包含子文件夹；输入变化会取消旧搜索 |
| 其他 | 显示隐藏文件/扩展名、复制路径、属性、在访达显示、当前目录变更自动刷新、深浅色随系统 |

## 使用要点

**缩略图与预览：** 在“查看”中选择大图标或超大图标，图片直接显示缩略图。单击文件可在右侧预览；空格打开独立的大预览窗口。图片预览支持缩放，PDF 支持系统的滚动与页面预览。

**移动文件：** 选择文件后剪切，进入目标文件夹粘贴，或者右键选择“移动到…”。拖放默认为复制，以便跨文件夹操作时行为明确。

**重名文件：** 自动生成 `文件名 (2).扩展名`，已有文件保持不变。文件夹重名时也保留两份，不自动合并目录。重命名到已存在的其他文件名会停止并提示。

**撤销：** 通过 ⌘Z 或工具栏弯箭头撤销。新建/复制/压缩的撤销会把创建的项目移到废纸篓。若目标已被其他文件占用，或原操作的文件已被替换/修改，撤销会停止，保留现有数据。撤销历史只保存在内存中，退出后清除，不提供重做。

**搜索：** 默认只搜索当前目录的名称。搜索框右侧下拉菜单可启用“包含子文件夹”。递归搜索跳过应用包内部，不跟随符号链接遍历；最多扫描 200,000 项或显示 20,000 个匹配结果，达到上限会明确提示。搜索不检索文件正文。无法访问的子目录会给出跳过提示。

**目录树：** 磁盘名称左侧的小箭头可逐层展开。每层最多显示 150 个目录、最多展开 16 层，超出时可点“更多文件夹…”在主区域浏览。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| 双击 / Enter | 打开所选项目 |
| Space | 大预览 |
| ← / →、Esc（预览窗口） | 上一项 / 下一项、关闭 |
| ⌘C / ⌘X / ⌘V | 复制 / 剪切 / 粘贴 |
| ⌘A | 全选 |
| Shift 点击 / ⌘ 点击 | 范围选择 / 多选 |
| ⌘Z | 撤销上次文件操作 |
| F2 | 重命名 |
| F5 / ⌘R | 刷新 |
| ⌘⌫ / 向前 Delete | 移到废纸篓 |
| Backspace | 后退 |
| ⌥← / ⌥→ / ⌥↑ | 后退 / 前进 / 上一级 |
| ⌘L / ⌘F | 输入路径 / 搜索 |
| ⌘T / ⌘W | 新建标签页 / 关闭标签页 |
| Ctrl Tab / Ctrl Shift Tab | 下一标签页 / 上一标签页 |
| ⌘N | 新建窗口 |
| ⌘⇧N | 新建文件夹 |
| ⌘1 / 2 / 3 / 4 | 详情 / 中 / 大 / 超大图标 |
| ⌘⇧. | 显示 / 隐藏隐藏文件 |
| ⌥⌘P | 显示 / 隐藏预览窗格 |
| ⌘⇧C / ⌘I | 复制路径 / 属性 |

文件区域同时兼容 Ctrl+C/X/V/A/Z/L/F/T/W 和 Ctrl+Shift+N。编辑文本时使用 macOS 的 ⌘ 快捷键。部分 Mac 键盘需要同时按 Fn 才能发送 F2/F5。

## 当前边界

- 这是 Windows 风格的独立文件管理器，不是 Microsoft 官方产品，也不会替换系统访达。
- 缩略图和预览覆盖范围受系统编解码器及已安装 Quick Look 扩展影响；不支持的格式显示文件图标，并可用默认应用打开。
- 为控制内存，独立图片预览的解码长边上限为 8192 像素；更大图片会降采样显示，“100%”指解码后的预览图。原文件不变，需查看超大图原始像素时使用默认图片应用。
- 暂未实现 Windows Shell 扩展、SMB 连接向导、文件内容索引、批量改名、文件夹体积递归计算、权限编辑或回收站独立界面。已挂载的网络盘可按路径访问；废纸篓在访达打开。
- ZIP 使用系统工具并保留符号链接本身，适合通用文件交换；不作为完整保留所有 macOS 扩展属性的备份格式。
- 大文件复制/压缩时显示当前任务；单个文件传输不提供字节级进度或中途取消。操作进行中关闭窗口/退出会被阻止。
- 当前目录的直接变更会自动刷新；递归搜索中的深层变化可按 F5 重新扫描。
- 拖放已实现原生协议，但本次自动化测试只观测到拖动开始，未收到落下事件，因此拖放未列入通过实测的功能。若在你的操作环境中遇到拖放问题，可使用已验证的复制粘贴、剪切粘贴或“复制到 / 移动到…”。

## 源码与构建

仓库包含全部源码、应用图标、Info.plist、构建脚本和文件操作测试。没有第三方依赖。

```bash
git clone https://github.com/leexhq/ExplorerMac.git
cd ExplorerMac
bash test.sh
bash build.sh
```

需要 Apple Command Line Tools。`build.sh` 为 arm64 和 x86_64 编译、合并为通用应用，并执行本地签名和签名校验。可传入输出目录：`bash build.sh /目标目录`。

主要文件：`ExplorerModel.swift` 管理导航、搜索、监控和任务状态；`FileCore.swift` 实现文件操作及撤销保护；`Browser.swift` 实现原生网格/表格与缩略图；`Preview.swift` 实现图片和 Quick Look；`ExplorerView.swift` 与 `FolderTree.swift` 构建界面；`App.swift` 提供窗口、菜单和快捷键。

技术参考：[Microsoft File Explorer](https://support.microsoft.com/en-us/windows/experience/fileexplorer/file-explorer-in-windows)、[Apple Quick Look](https://developer.apple.com/documentation/quartz/quick-look/)、[Apple 缩略图 API](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator/request)。

## 许可证

本项目使用 [MIT License](LICENSE)。
