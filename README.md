# x-file

<p align="center">
  <img src="assets/icon/x-file-icon-1024.png" width="132" alt="x-file icon">
</p>

<p align="center">
  一个面向本地文件的跨平台阅读、预览与编辑工作台。
</p>

<p align="center">
  <a href="#核心能力">核心能力</a> ·
  <a href="#支持的文件">支持的文件</a> ·
  <a href="#开始使用">开始使用</a> ·
  <a href="#构建发布">构建发布</a>
</p>

## 项目简介

**x-file** 是使用 Flutter 构建的本地文件工作台。它将文件树、编辑器、预览、目录和终端放进一个紧凑的桌面界面，适合阅读文档、浏览项目文件和进行轻量编辑。

Markdown 是当前的重点体验：默认以预览方式打开，支持在预览中直接编辑、目录定位和内容查找。HTML 文件可使用原生 WebView 预览，也可一键交给 Chrome 打开。编辑器同时为常见文本与代码文件提供语法高亮。

## 核心能力

- **多工作区与多文档**：同时打开多个文件夹或独立文件，在顶部标签间快速切换。
- **文件树**：文件夹层级浏览、过滤、单链目录压缩展示，以及按文件类型区分的图标。
- **Markdown 工作流**：预览、源码和分栏三种视图；预览区域支持直接编辑、复制、目录跳转与查找高亮。
- **HTML 预览**：在应用内预览本地 HTML，并支持使用 Chrome 打开。
- **代码编辑**：面向 Markdown、JSON、YAML、Java、Python、TypeScript、JavaScript、HTML、CSS、SQL、Shell 等格式的文本编辑与语法高亮。
- **目录导航**：从 Markdown 标题自动生成可折叠大纲，默认展开一级；点击标题平滑定位到对应内容。
- **查找与替换**：当前文件查找、预览内查找、文件夹范围的全局查找与替换。
- **实时同步**：监听已打开的本地文件和文件夹；外部文件变化会同步提示或刷新。
- **会话恢复**：启动时重新载入上次打开的文件和目录，保留最近打开的 10 项记录。
- **内置终端**：从当前工作区路径启动 Shell，在应用底部执行命令并查看输出。
- **主题与界面**：提供亮色和暗色主题；当前亮色主题采用克制的白色基底与蓝色强调。

## 支持的文件

| 类型 | 当前能力 |
| --- | --- |
| `.md` / `.markdown` | 可视化预览、预览内编辑、源码编辑、目录、查找 |
| `.html` / `.htm` | 应用内预览、Chrome 打开、源码编辑 |
| `.java` / `.py` / `.ts` / `.js` / `.json` / `.yaml` / `.yml` / `.xml` / `.css` / `.sql` / `.sh` | 源码编辑与语法高亮 |
| 其他文本文件 | 打开、编辑、保存与文件树浏览 |

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `Command + O` | 打开文件 |
| `Command + Shift + O` | 打开文件夹 |
| `Command + S` | 保存当前文件 |
| `Command + F` | 查找当前文件或 Markdown 预览内容 |
| `Command + Shift + F` | 全局查找 |
| `Command + Shift + H` | 全局替换 |
| `Command + B` | 折叠或展开文件侧栏 |

Windows 和 Linux 使用 `Ctrl` 替代 `Command`。

## 开始使用

### 环境要求

- Flutter SDK `3.12` 或更高版本
- Dart SDK（由 Flutter 提供）
- 对应平台的桌面构建环境
  - macOS：Xcode Command Line Tools
  - Windows：Visual Studio（Desktop development with C++）
  - Linux：系统桌面构建依赖

### 本地运行

```bash
git clone https://github.com/tghrxxxyyy/x-file.git
cd x-file
flutter pub get
flutter run -d macos
```

将 `macos` 替换为 `windows` 或 `linux`，即可运行相应桌面端。

## 构建发布

```bash
# macOS Apple Silicon 正式构建
flutter build macos --release

# Windows 正式构建
flutter build windows --release

# Linux 正式构建
flutter build linux --release
```

macOS 的 Release 配置固定为 **ARM64**，面向 Apple Silicon 设备发布。构建产物位于对应平台的 `build/<platform>/Build/Products/Release/` 目录。

## 项目结构

```text
lib/
├── models/       # 文档、文件树、工作区与搜索模型
├── services/     # 文件系统、文件监听、会话、搜索和终端服务
├── state/        # 应用与编辑会话状态
├── widgets/      # 桌面界面、预览、编辑器、终端与侧栏
├── app_theme.dart
└── main.dart
assets/
├── fonts/        # Maple Mono CN 字体
├── icon/         # 应用图标
└── terminal/     # 终端资源
```

## 技术栈

- [Flutter](https://flutter.dev/) / Dart
- `re_editor` 与 `re_highlight`：代码编辑和语法高亮
- `webview_flutter`：HTML 与 Markdown DOM 预览
- `watcher`：本地文件变化监听
- `file_selector`：原生文件与目录选择

## 路线图

- 增强更多代码语言的编辑体验与语言服务集成
- 补充 PDF、Office 等常用文件格式的展示能力
- 持续完善 Windows 与 Linux 平台的原生体验

---

本项目当前以桌面端本地文件工作流为核心，不会上传或托管用户打开的文件内容。
