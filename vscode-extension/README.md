# Nexora Markdown Preview

把 [Nexora](https://github.com/Zcorpius/Nexora) 的 Markdown 预览主题移植到 **VS Code 内置** Markdown 预览:渐变标题、悬停动画、GitHub callouts、Mac 风代码块、highlight.js 与 Mermaid,并让配色跟随你当前的 VS Code 主题。

>[!IMPORTANT]
> **重要:本扩展只对 VS Code 内置预览生效。**
> 如果你装了 **Markdown Preview Enhanced**(`shd101wyy.markdown-preview-enhanced`),它会接管 `Cmd/Ctrl+Shift+V`,本扩展的样式**不会生效**。两种解决办法:
> - 卸载/禁用 MPE:`code --uninstall-extension shd101wyy.markdown-preview-enhanced`,之后 `Cmd/Ctrl+Shift+V` 回归内置预览;
> - 或保留 MPE,改用命令面板里的 **「Markdown: Open Preview to the Side」**(VS Code 内置,不是带 Enhanced 的那个)。
>
> 判断方法:预览顶部如果有 MPE 的工具栏 / 右键菜单有 MPE 选项,就是 MPE 在接管。

## 特性

- **标题**:H1 底部渐变线、H2 渐变色块、H3 装饰条、H4/H5 圆点、H6 长划线,全部带悬停动画
- **GitHub callouts**:`> [!NOTE] / [!TIP] / [!WARNING] / [!IMPORTANT] / [!CAUTION]` 五种卡片
- **代码块**:Mac 三色点 + 语言标签外壳;内置完整 **highlight.js 11**，支持 192 种语言(与 Nexora 同配色)
- **Mermaid**:` ```mermaid ` 代码块渲染为图表,跟随明 / 暗主题；使用 Nexora 独立运行时，避免与 VS Code 1.131+ 内置 Mermaid 扩展冲突
- **`[TOC]`** 自动目录、图片 `<figure>` 说明
- **配色联动 VS Code 主题**:背景 / 文字 / 边框 / 表面 / 滚动条 / 链接主色全部跟随当前 VS Code 主题,切主题即变
- **铺满渲染**:预览内容铺满宽度,无两侧空白
- **YAML front matter**:可选显示为 Nexora「YAML」卡片

## 安装

### 从 .vsix 安装

```bash
code --install-extension nexora-markdown-0.4.6.vsix
```

或在 VS Code 里:`扩展` 面板 → 右上角 `···` → `从 VSIX 安装`,选择 `nexora-markdown-0.4.6.vsix`。

安装后 **Reload Window**,打开任意 `.md` 文件 → 用内置预览打开(见上方「重要」)。

## 配色联动说明

| 元素 | 行为 |
|---|---|
| 背景 / 文字 / 边框 / 表面色 / 滚动条 | 跟随 VS Code 主题(`--vscode-editor-background` 等) |
| 主色(H1/H2 渐变、链接、装饰) | 跟随 VS Code 链接色(`--vscode-textLink-foreground`) |
| 代码语法 token(coral / acid / amber) | 保留 Nexora 配色¹ |
| 明 / 暗 | 自动(`vscode-dark` / `vscode-high-contrast`) |

¹ VS Code 不把语法高亮的 TextMate 颜色暴露为 CSS 变量,因此代码 token 色无法跟随主题,保留 Nexora 风格。其余视觉全部跟随。

## 适配说明 / 已知限制

- 通过 VS Code 官方扩展点 `markdown.previewStyles` + `markdown.previewScripts` + `markdown.markdownItPlugins` 注入,**不替换预览引擎**。
- **Front matter**:扩展会在解析阶段优先接管 YAML front matter，始终显示为 Nexora 的 YAML 卡片，不受 VS Code 默认 `markdown.preview.frontMatter: "table"` 影响。
- **脚注**:在解析阶段支持 `[^id]` 引用与定义（包括多行内容和重复引用），输出 Nexora 脚注卡片。
- **字体**:优先 `Maple Mono`,缺失时回退 `SF Mono / Consolas / monospace`。
- **只读预览**:不支持 Nexora 桌面端的 contenteditable 直接编辑;VS Code 预览本身是只读的。

## 本地开发调试

主题样式写在 `media/nexora.src.css`(用 CSS Nesting,便于维护),构建时由 PostCSS 编译成扁平 CSS(`media/nexora.css`)——**VS Code 的 markdown 预览不支持原生 CSS Nesting,必须编译成扁平选择器才能生效**。

```bash
cd vscode-extension
npm install
npm run build       # 编译 CSS + 生成完整 highlight.js 浏览器包
npm run package     # 编译 + 打包 .vsix
```

调试运行:`code --extensionDevelopmentPath=.`

## 主题来源

CSS / JS 移植自 Nexora 主项目 `lib/widgets/markdown_dom_preview.dart` 的 `_styleSheet()` 与 `_bridgeScript`。
