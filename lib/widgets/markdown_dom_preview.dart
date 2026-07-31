import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../models/markdown_heading.dart';
import '../models/markdown_theme.dart';
import '../services/markdown_asset_resolver.dart';
import '../services/markdown_code_highlighter.dart';
import '../services/markdown_preview_theme.dart';
import '../state/preview_find_controller.dart';
import 'preview_find_panel.dart';

class MarkdownDomPreview extends StatefulWidget {
  const MarkdownDomPreview({
    required this.path,
    required this.workspaceRoot,
    required this.content,
    required this.headings,
    required this.previewAnchor,
    required this.previewJumpId,
    required this.findController,
    required this.themeMode,
    required this.markdownTheme,
    required this.fontScale,
    this.onContentChanged,
    this.onOpenLocalPath,
    this.onOpenAnchor,
    super.key,
  });

  final String path;
  final String workspaceRoot;
  final String content;
  final List<MarkdownHeading> headings;
  final String? previewAnchor;
  final int previewJumpId;
  final PreviewFindController findController;
  final AppThemeMode themeMode;
  final MarkdownTheme markdownTheme;
  final double fontScale;
  final ValueChanged<String>? onContentChanged;
  final ValueChanged<String>? onOpenLocalPath;
  final ValueChanged<String>? onOpenAnchor;

  @override
  State<MarkdownDomPreview> createState() => _MarkdownDomPreviewState();
}

class _MarkdownDomPreviewState extends State<MarkdownDomPreview> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _pageReady = false;
  String? _error;
  String? _pendingAnchor;
  int _observedFocusRequestId = 0;
  int _observedNavigationRequestId = 0;
  bool _observedFindOpen = false;
  bool _observedCaseSensitive = false;
  String _observedFindQuery = '';
  String? _pendingPreviewContent;

  late final MarkdownCodeHighlighter _codeHighlighter =
      MarkdownCodeHighlighter();

  @override
  void initState() {
    super.initState();
    _observedFocusRequestId = widget.findController.focusRequestId;
    _observedNavigationRequestId = widget.findController.navigationRequestId;
    _observedFindOpen = widget.findController.isOpen;
    _observedCaseSensitive = widget.findController.caseSensitive;
    _observedFindQuery = widget.findController.query;
    _pendingAnchor = widget.previewAnchor;
    widget.findController.addListener(_handleFindChanged);
    _initializeWebView();
  }

  void _initializeWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'NexoraBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _pageReady = false;
                _loading = true;
              });
            }
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _pageReady = true;
              _loading = false;
            });
            unawaited(_flushPageCommands());
          },
          onNavigationRequest: (request) {
            return request.url.startsWith('file://') ||
                    request.url == 'about:blank'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _error = error.description);
          },
        ),
      );
    _controller = controller;
    unawaited(_loadContent());
  }

  @override
  void didUpdateWidget(MarkdownDomPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.findController != oldWidget.findController) {
      oldWidget.findController.removeListener(_handleFindChanged);
      _observedFocusRequestId = widget.findController.focusRequestId;
      _observedNavigationRequestId = widget.findController.navigationRequestId;
      _observedFindOpen = widget.findController.isOpen;
      _observedCaseSensitive = widget.findController.caseSensitive;
      _observedFindQuery = widget.findController.query;
      widget.findController.addListener(_handleFindChanged);
    }
    final contentCameFromPreview =
        _pendingPreviewContent != null &&
        widget.content == _pendingPreviewContent;
    if (contentCameFromPreview) {
      _pendingPreviewContent = null;
      unawaited(_updateHeadingAnchors());
    } else if (widget.themeMode != oldWidget.themeMode ||
        widget.markdownTheme != oldWidget.markdownTheme) {
      unawaited(_refreshThemedDocument());
    } else if (widget.fontScale != oldWidget.fontScale) {
      unawaited(
        _runJavaScript('window.nexoraSetFontScale(${widget.fontScale});'),
      );
    } else if (widget.content != oldWidget.content ||
        widget.path != oldWidget.path ||
        widget.headings != oldWidget.headings) {
      unawaited(_replaceDocument());
    }
    if (widget.previewJumpId != oldWidget.previewJumpId) {
      _pendingAnchor = widget.previewAnchor;
      unawaited(_flushPageCommands());
    }
  }

  @override
  void dispose() {
    widget.findController.removeListener(_handleFindChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundRaised,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.signal,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _error!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.coral, fontSize: 10),
                ),
              ),
            ),
          Align(
            alignment: Alignment.topRight,
            child: ListenableBuilder(
              listenable: widget.findController,
              builder: (context, child) => AnimatedSwitcher(
                duration: AppMotion.standard,
                reverseDuration: AppMotion.quick,
                switchInCurve: AppMotion.emphasized,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, -0.08),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: widget.findController.isOpen
                    ? PreviewFindPanel(
                        key: const ValueKey('preview-find-panel'),
                        controller: widget.findController,
                      )
                    : const SizedBox(key: ValueKey('preview-find-closed')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadContent() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _pageReady = false;
        _error = null;
      });
    }
    try {
      final baseUrl = Uri.directory(
        '${p.dirname(widget.path)}${Platform.pathSeparator}',
      ).toString();
      await _controller.loadHtmlString(_documentHtml(), baseUrl: baseUrl);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _refreshThemedDocument() async {
    await _loadContent();
  }

  Future<void> _replaceDocument() async {
    if (!_pageReady) {
      await _loadContent();
      return;
    }
    final baseUrl = Uri.directory(
      '${p.dirname(widget.path)}${Platform.pathSeparator}',
    ).toString();
    await _runJavaScript(
      'window.nexoraReplaceDocument('
      '${jsonEncode(_markdownHtml())}, ${jsonEncode(baseUrl)}'
      ');',
    );
    await _updateHeadingAnchors();
    await _syncFind(force: true);
  }

  Future<void> _updateHeadingAnchors() {
    final anchors = widget.headings.map((heading) => heading.anchor).toList();
    return _runJavaScript('window.nexoraSetAnchors(${jsonEncode(anchors)});');
  }

  Future<void> _flushPageCommands() async {
    if (!_pageReady) return;
    await _runJavaScript('requestAnimationFrame(() => window.nexoraReady());');
    await _updateHeadingAnchors();
    final anchor = _pendingAnchor;
    _pendingAnchor = null;
    if (anchor != null && anchor.isNotEmpty) {
      await _runJavaScript('window.nexoraScrollTo(${jsonEncode(anchor)});');
    }
    await _syncFind(force: true);
  }

  void _handleFindChanged() {
    final findController = widget.findController;
    final focusRequested =
        findController.focusRequestId != _observedFocusRequestId;
    if (focusRequested) {
      _observedFocusRequestId = findController.focusRequestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !findController.isOpen) return;
        findController.focusNode.requestFocus();
        findController.queryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: findController.query.length,
        );
      });
    }
    unawaited(_syncFind());
  }

  Future<void> _syncFind({bool force = false}) async {
    final findController = widget.findController;
    final searchChanged =
        force ||
        findController.isOpen != _observedFindOpen ||
        findController.query != _observedFindQuery ||
        findController.caseSensitive != _observedCaseSensitive;
    final navigationChanged =
        findController.navigationRequestId != _observedNavigationRequestId;
    _observedFindOpen = findController.isOpen;
    _observedFindQuery = findController.query;
    _observedCaseSensitive = findController.caseSensitive;
    _observedNavigationRequestId = findController.navigationRequestId;
    if (!_pageReady) return;
    if (!findController.isOpen) {
      await _runJavaScript('window.nexoraClearFind();');
      return;
    }
    if (searchChanged) {
      await _runJavaScript(
        'window.nexoraFind('
        '${jsonEncode(findController.query)}, '
        '${findController.caseSensitive}, '
        '${findController.activeIndex}, '
        '${navigationChanged || force}'
        ');',
      );
      return;
    }
    if (navigationChanged) {
      await _runJavaScript(
        'window.nexoraActivate(${findController.activeIndex}, true);',
      );
    }
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    try {
      final value = jsonDecode(message.message);
      if (value is! Map) return;
      final type = value['type'];
      if (type == 'find') {
        final count = value['count'];
        if (count is! num) return;
        widget.findController.updateMatchCount(count.toInt());
        unawaited(
          _runJavaScript(
            'window.nexoraActivate(${widget.findController.activeIndex}, false);',
          ),
        );
        return;
      }
      if (type == 'content') {
        final markdown = value['markdown'];
        if (markdown is! String || markdown == widget.content) return;
        _pendingPreviewContent = markdown;
        widget.onContentChanged?.call(markdown);
        return;
      }
      if (type == 'image') {
        final source = value['src'];
        if (source is String) _openImage(source);
        return;
      }
      final href = value['href'];
      if (type == 'link' && href is String) _openLink(href);
    } catch (_) {}
  }

  void _openLink(String href) {
    final decodedHref = Uri.decodeFull(href);
    if (decodedHref.startsWith('#')) {
      final anchor = _resolveAnchor(
        Uri.decodeComponent(decodedHref.substring(1)),
      );
      if (anchor != null) widget.onOpenAnchor?.call(anchor);
      return;
    }
    final uri = Uri.tryParse(decodedHref);
    if (uri != null && uri.hasScheme) {
      unawaited(_openExternal(uri.toString()));
      return;
    }
    final fragmentIndex = decodedHref.indexOf('#');
    final relativePath = fragmentIndex < 0
        ? decodedHref
        : decodedHref.substring(0, fragmentIndex);
    if (relativePath.isEmpty) return;
    final localPath = p.normalize(p.join(p.dirname(widget.path), relativePath));
    widget.onOpenLocalPath?.call(localPath);
  }

  void _openImage(String source) {
    final decodedSource = Uri.decodeFull(source);
    final uri = Uri.tryParse(decodedSource);
    if (uri != null && uri.scheme == 'file') {
      widget.onOpenLocalPath?.call(uri.toFilePath());
      return;
    }
    if (uri != null && uri.hasScheme) {
      unawaited(_openExternal(uri.toString()));
      return;
    }
    widget.onOpenLocalPath?.call(
      p.normalize(p.join(p.dirname(widget.path), decodedSource)),
    );
  }

  String? _resolveAnchor(String requestedAnchor) {
    for (final heading in widget.headings) {
      if (heading.anchor == requestedAnchor) return heading.anchor;
    }
    final requestedTitle = _anchorTitle(requestedAnchor);
    final matches = widget.headings
        .where((heading) => _anchorTitle(heading.anchor) == requestedTitle)
        .toList(growable: false);
    return matches.length == 1 ? matches.single.anchor : null;
  }

  String _anchorTitle(String anchor) {
    final normalized = anchor
        .toLowerCase()
        .replaceAll(RegExp(r'[\\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceFirst(RegExp(r'^-+'), '')
        .replaceFirst(RegExp(r'-+$'), '');
    final separator = normalized.indexOf('-');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }

  Future<void> _openExternal(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  }

  Future<void> _runJavaScript(String script) async {
    try {
      await _controller.runJavaScript(script);
    } catch (_) {}
  }

  String _documentHtml() {
    final markdownHtml = _markdownHtml();
    final baseUrl = Uri.directory(
      '${p.dirname(widget.path)}${Platform.pathSeparator}',
    ).toString();
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="${const HtmlEscape().convert(baseUrl)}">
<style>${_styleSheet()}</style>
</head>
<body>
<main id="nexora-document" contenteditable="true" spellcheck="false" tabindex="0">$markdownHtml</main>
<script>$_bridgeScript</script>
</body>
</html>''';
  }

  String _markdownHtml() {
    final html = md.markdownToHtml(
      widget.content,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    var headingIndex = 0;
    final anchoredHtml = html.replaceAllMapped(RegExp(r'<h([1-6])>'), (match) {
      if (headingIndex >= widget.headings.length) return match.group(0)!;
      final anchor = const HtmlEscape().convert(
        widget.headings[headingIndex++].anchor,
      );
      return '<h${match.group(1)} id="$anchor">';
    });
    return _codeHighlighter.decorate(_resolveLocalImageSources(anchoredHtml));
  }

  String _resolveLocalImageSources(String html) {
    return html.replaceAllMapped(
      RegExp(r'(<img\b[^>]*\bsrc=")([^"]*)(")', caseSensitive: false),
      (match) {
        final imagePath = MarkdownAssetResolver.resolveLocalPath(
          source: match.group(2)!,
          documentPath: widget.path,
          workspaceRoot: widget.workspaceRoot,
        );
        if (imagePath == null) return match.group(0)!;
        final dataUri = MarkdownAssetResolver.dataUriForPath(imagePath);
        if (dataUri == null) return match.group(0)!;
        return '${match.group(1)}$dataUri${match.group(3)}';
      },
    );
  }

  String _styleSheet() {
    final dark = widget.themeMode == AppThemeMode.dark;
    return '''
:root { color-scheme: ${dark ? 'dark' : 'light'}; --nexora-font-scale: ${widget.fontScale}; }
* { box-sizing: border-box; }
html {
  width: 100%;
  min-height: 100%;
  background: ${_color(AppColors.backgroundRaised)};
  scroll-behavior: smooth;
}
body {
  margin: 0;
  width: 100%;
  min-height: 100vh;
  color: ${_color(AppColors.text)};
  background: ${_color(AppColors.background)};
  font-family: "Maple Mono", "SF Mono", "PingFang SC", "Noto Sans CJK SC", monospace;
  font-size: calc(15px * var(--nexora-font-scale));
  line-height: 1.72;
  letter-spacing: 0;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
#nexora-document {
  width: min(100%, 1120px);
  margin: 0 auto;
  padding: 36px 46px 96px;
  outline: none;
  caret-color: ${_color(AppColors.signal)};
  -webkit-user-select: text;
  user-select: text;
}
#nexora-document, #nexora-document * { -webkit-user-select: text; user-select: text; }
#nexora-document:focus { background: transparent; }
h1, h2, h3, h4, h5, h6 { scroll-margin-top: 28px; color: ${_color(AppColors.text)}; }
h1 { margin: 10px 0 14px; font-size: calc(31px * var(--nexora-font-scale)); font-weight: 300; line-height: 1.35; }
h2 { margin: 22px 0 10px; font-size: calc(23px * var(--nexora-font-scale)); font-weight: 600; line-height: 1.4; }
h3 { margin: 18px 0 8px; color: ${_color(AppColors.text)}; font-size: calc(18px * var(--nexora-font-scale)); font-weight: 600; line-height: 1.45; }
h4 { margin: 14px 0 7px; font-size: calc(15px * var(--nexora-font-scale)); font-weight: 700; }
h5 { margin: 14px 0 7px; color: ${_color(AppColors.textMuted)}; font-size: calc(14px * var(--nexora-font-scale)); font-weight: 700; }
h6 { margin: 14px 0 7px; color: ${_color(AppColors.textMuted)}; font-size: calc(12px * var(--nexora-font-scale)); font-weight: 700; }
p { margin: 0 0 8px; }
a { color: ${_color(AppColors.signal)}; text-decoration-color: ${_color(AppColors.signalDim)}; text-underline-offset: 3px; }
strong { color: ${_color(AppColors.text)}; font-weight: 700; }
em { font-style: italic; }
code {
  color: ${_color(AppColors.text)};
  background: rgba(${_rgb(AppColors.signal)}, 0.07);
  border-radius: 3px;
  padding: 0.12em 0.34em;
  font-family: "Maple Mono", "SF Mono", monospace;
  font-size: 0.88em;
}
pre {
  margin: 14px 0;
  overflow: auto;
  padding: 18px;
  color: ${_color(AppColors.text)};
  background: ${_color(AppColors.surface)};
  border-radius: 5px;
}
pre code { padding: 0; color: inherit; background: transparent; }
.nexora-code-block {
  position: relative;
  margin: 16px 0;
  overflow: hidden;
  background: #f6faff;
  border: 0;
  border-radius: 7px;
  box-shadow: none;
}
.nexora-code-block pre {
  margin: 0;
  padding: 39px 20px 20px;
  border-radius: 0;
  background: transparent;
  font-family: "Maple Mono", "SF Mono", Consolas, monospace;
  font-size: calc(13px * var(--nexora-font-scale));
  line-height: 1.68;
  tab-size: 2;
}
.nexora-code-language {
  position: absolute;
  z-index: 1;
  top: 10px;
  right: 12px;
  display: inline-flex;
  align-items: center;
  min-height: 19px;
  padding: 1px 7px;
  color: ${_color(AppColors.signal)};
  background: rgba(${_rgb(AppColors.signal)}, 0.075);
  border: 0;
  border-radius: 999px;
  font-family: "Maple Mono", "SF Mono", monospace;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.04em;
  line-height: 1.5;
  text-transform: lowercase;
  -webkit-user-select: none;
  user-select: none;
  pointer-events: none;
}
.hljs-comment, .hljs-quote { color: ${_color(AppColors.textDim)}; font-style: italic; }
.hljs-keyword, .hljs-selector-tag, .hljs-literal, .hljs-meta .hljs-keyword { color: ${_color(AppColors.coral)}; }
.hljs-string, .hljs-doctag, .hljs-regexp { color: ${_color(AppColors.amber)}; }
.hljs-number, .hljs-symbol, .hljs-bullet { color: ${_color(AppColors.amber)}; }
.hljs-title, .hljs-function, .hljs-type, .hljs-class .hljs-title { color: ${_color(AppColors.signal)}; }
.hljs-params, .hljs-variable, .hljs-template-variable, .hljs-attr { color: ${_color(AppColors.textMuted)}; }
.hljs-built_in, .hljs-meta, .hljs-tag, .hljs-name { color: ${_color(AppColors.signalDim)}; }
.hljs-attribute, .hljs-property { color: ${_color(AppColors.amber)}; }
blockquote {
  margin: 14px 0;
  padding: 10px 16px;
  color: ${_color(AppColors.textMuted)};
  background: #f7f8ff;
}
ul, ol { padding-left: 28px; }
li::marker { color: ${_color(AppColors.signal)}; }
hr { height: 1px; border: 0; background: rgba(${_rgb(AppColors.signal)}, 0.30); margin: 24px 0; }
table { width: 100%; margin: 14px 0; border-collapse: separate; border-spacing: 0 5px; overflow: hidden; }
thead tr { background: #f3f8fd; }
tbody tr { background: #fbfcfe; }
th, td { padding: 10px 14px; vertical-align: top; text-align: left; }
th { color: ${_color(AppColors.text)}; font-weight: 700; }
td { font-size: 13px; }
img { display: block; max-width: 100%; height: auto; margin: 16px 0; cursor: zoom-in; -webkit-user-drag: none; }
mark.nexora-find { color: inherit; background: rgba(${_rgb(AppColors.amber)}, 0.30); border-radius: 3px; padding: 0 1px; }
mark.nexora-find.nexora-find-active { background: rgba(${_rgb(AppColors.signal)}, 0.36); }
::-webkit-scrollbar { width: 9px; height: 9px; }
::-webkit-scrollbar-thumb { background: rgba(${_rgb(AppColors.lineStrong)}, 0.78); border: 2px solid transparent; border-radius: 999px; background-clip: padding-box; }
::-webkit-scrollbar-track { background: transparent; }
@media (max-width: 720px) { #nexora-document { padding: 24px 22px 72px; } h1 { font-size: 27px; } h2 { font-size: 21px; } }
${MarkdownPreviewTheme.css(widget.markdownTheme)}''';
  }

  String _color(Color color) =>
      '#${(color.toARGB32() & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';

  String _rgb(Color color) {
    final value = color.toARGB32();
    return '${(value >> 16) & 0xff}, ${(value >> 8) & 0xff}, ${value & 0xff}';
  }
}

const _bridgeScript = r'''
window.nexoraReady = function() {};
window.nexoraSetFontScale = function(value) {
  document.documentElement.style.setProperty('--nexora-font-scale', value);
};
window.nexoraMatches = [];
window.nexoraInputTimer = null;
window.nexoraSelectionTimer = null;
window.nexoraPendingContentSync = false;

window.nexoraPostMessage = function(message) {
  if (window.NexoraBridge && window.NexoraBridge.postMessage) {
    window.NexoraBridge.postMessage(JSON.stringify(message));
    return;
  }
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage(message);
  }
};

window.nexoraSetAnchors = function(anchors) {
  var headings = document.querySelectorAll('#nexora-document h1, #nexora-document h2, #nexora-document h3, #nexora-document h4, #nexora-document h5, #nexora-document h6');
  headings.forEach(function(heading, index) {
    heading.id = anchors[index] || '';
  });
};

window.nexoraToMarkdown = function(root) {
  function children(node) {
    return Array.prototype.map.call(node.childNodes, serialize).join('');
  }

  function inlineChildren(node) {
    return Array.prototype.map.call(node.childNodes, serialize).join('').trim();
  }

  function list(node, ordered) {
    var items = Array.prototype.filter.call(node.children, function(child) {
      return child.tagName === 'LI';
    });
    var lines = items.map(function(item, index) {
      var body = '';
      var nested = [];
      Array.prototype.forEach.call(item.childNodes, function(child) {
        if (child.nodeType === Node.ELEMENT_NODE &&
            (child.tagName === 'UL' || child.tagName === 'OL')) {
          nested.push(list(child, child.tagName === 'OL').trim());
        } else {
          body += serialize(child);
        }
      });
      var prefix = ordered ? (index + 1) + '. ' : '- ';
      var result = prefix + body.trim();
      if (nested.length) result += '\n' + nested.map(function(value) {
        return value.split('\n').map(function(line) {
          return line ? '  ' + line : line;
        }).join('\n');
      }).join('\n');
      return result;
    });
    return lines.join('\n') + '\n\n';
  }

  function table(node) {
    var rows = Array.prototype.map.call(node.querySelectorAll('tr'), function(row) {
      return Array.prototype.map.call(row.children, function(cell) {
        return inlineChildren(cell).replace(/\|/g, '\\|').replace(/\n+/g, ' ');
      });
    }).filter(function(row) { return row.length; });
    if (!rows.length) return '';
    var output = ['| ' + rows[0].join(' | ') + ' |'];
    output.push('| ' + rows[0].map(function() { return '---'; }).join(' | ') + ' |');
    rows.slice(1).forEach(function(row) {
      output.push('| ' + row.join(' | ') + ' |');
    });
    return output.join('\n') + '\n\n';
  }

  function serialize(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return (node.nodeValue || '').replace(/\u00a0/g, ' ');
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    var tag = node.tagName.toLowerCase();
    var value = children(node);
    if (node.classList.contains('nexora-code-language')) return '';
    if (node.classList.contains('nexora-code-block')) {
      var fencedCode = node.querySelector('pre code');
      var fencedLanguage = node.dataset.nexoraLanguage || '';
      var fence = fencedLanguage && fencedLanguage !== 'text' ? fencedLanguage : '';
      return '```' + fence + '\n' +
          ((fencedCode && fencedCode.textContent) || '').replace(/^\n+|\n+$/g, '') +
          '\n```\n\n';
    }
    if (tag === 'br') return '\n';
    if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      return '#'.repeat(Number(tag.substring(1))) + ' ' + inlineChildren(node) + '\n\n';
    }
    if (tag === 'p' || tag === 'div') return value.trim() + '\n\n';
    if (tag === 'strong' || tag === 'b') return '**' + value.trim() + '**';
    if (tag === 'em' || tag === 'i') return '*' + value.trim() + '*';
    if (tag === 'del' || tag === 's' || tag === 'strike') return '~~' + value.trim() + '~~';
    if (tag === 'code') return '`' + (node.textContent || '').replace(/`/g, '\\`') + '`';
    if (tag === 'pre') {
      var code = node.querySelector('code');
      var className = (code && code.className) || '';
      var match = className.match(/(?:^|\s)language-([^\s]+)/);
      var language = match ? match[1] : '';
      return '```' + language + '\n' +
          (node.textContent || '').replace(/^\n+|\n+$/g, '') + '\n```\n\n';
    }
    if (tag === 'blockquote') {
      return value.trim().split('\n').map(function(line) {
        return line ? '> ' + line : '>';
      }).join('\n') + '\n\n';
    }
    if (tag === 'ul' || tag === 'ol') return list(node, tag === 'ol');
    if (tag === 'table') return table(node);
    if (tag === 'hr') return '---\n\n';
    if (tag === 'a') return '[' + value.trim() + '](' + (node.getAttribute('href') || '') + ')';
    if (tag === 'img') return '![' + (node.getAttribute('alt') || '') + '](' + (node.getAttribute('src') || '') + ')';
    return value;
  }

  var markdown = children(root)
      .replace(/\n{3,}/g, '\n\n')
      .replace(/^\s+|\s+$/g, '');
  return markdown ? markdown + '\n' : '';
};

window.nexoraSendContent = function() {
  var root = document.getElementById('nexora-document');
  if (!root) return;
  var selection = window.getSelection();
  if (selection && !selection.isCollapsed) {
    window.nexoraPendingContentSync = true;
    return;
  }
  window.nexoraPendingContentSync = false;
  window.nexoraClearFind();
  window.nexoraPostMessage({
    type: 'content',
    markdown: window.nexoraToMarkdown(root)
  });
};

window.nexoraAttachEditor = function() {
  var root = document.getElementById('nexora-document');
  if (!root || root.dataset.nexoraEditorAttached) return;
  root.dataset.nexoraEditorAttached = 'true';
  root.addEventListener('input', function() {
    window.clearTimeout(window.nexoraInputTimer);
    window.nexoraInputTimer = window.setTimeout(window.nexoraSendContent, 220);
  });
  root.addEventListener('pointerdown', function() {
    window.clearTimeout(window.nexoraSelectionTimer);
  }, true);
  root.addEventListener('pointerup', function() {
    window.requestAnimationFrame(function() {
      var selection = window.getSelection();
      if (selection && !selection.isCollapsed) return;
      root.focus({ preventScroll: true });
    });
  }, true);
  document.addEventListener('selectionchange', function() {
    if (!window.nexoraPendingContentSync) return;
    var selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    window.clearTimeout(window.nexoraSelectionTimer);
    window.nexoraSelectionTimer = window.setTimeout(window.nexoraSendContent, 80);
  });
};

window.nexoraReplaceDocument = function(html, baseHref) {
  window.nexoraClearFind();
  var root = document.getElementById('nexora-document');
  if (!root) return;
  root.contentEditable = 'true';
  root.innerHTML = html;
  var base = document.querySelector('base');
  if (base) base.href = baseHref;
  window.scrollTo({ top: 0, behavior: 'instant' });
  window.nexoraAttachEditor();
};

window.nexoraClearFind = function() {
  document.querySelectorAll('mark[data-nexora-find]').forEach(function(mark) {
    mark.replaceWith(document.createTextNode(mark.textContent || ''));
  });
  var root = document.getElementById('nexora-document');
  if (root) root.normalize();
  window.nexoraMatches = [];
};

window.nexoraActivate = function(requestedIndex, shouldScroll) {
  var matches = window.nexoraMatches || [];
  matches.forEach(function(match) {
    match.classList.remove('nexora-find-active');
  });
  if (!matches.length) return;
  var index = Number(requestedIndex);
  if (!Number.isFinite(index) || index < 0) index = 0;
  index = index % matches.length;
  var active = matches[index];
  active.classList.add('nexora-find-active');
  if (shouldScroll) {
    active.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
  }
};

window.nexoraFind = function(query, caseSensitive, requestedIndex, shouldScroll) {
  window.nexoraClearFind();
  if (!query) {
    window.nexoraPostMessage({ type: 'find', count: 0 });
    return;
  }
  var root = document.getElementById('nexora-document');
  if (!root) return;
  var needle = caseSensitive ? query : query.toLocaleLowerCase();
  var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: function(node) {
      var parent = node.parentElement;
      if (!parent || parent.closest('script, style, .nexora-code-language')) return NodeFilter.FILTER_REJECT;
      return node.nodeValue ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    }
  });
  var nodes = [];
  var node;
  while ((node = walker.nextNode())) nodes.push(node);
  nodes.forEach(function(textNode) {
    var text = textNode.nodeValue || '';
    var comparable = caseSensitive ? text : text.toLocaleLowerCase();
    var start = 0;
    var found = comparable.indexOf(needle, start);
    if (found < 0) return;
    var fragment = document.createDocumentFragment();
    while (found >= 0) {
      if (found > start) fragment.appendChild(document.createTextNode(text.slice(start, found)));
      var mark = document.createElement('mark');
      mark.className = 'nexora-find';
      mark.dataset.nexoraFind = '1';
      mark.textContent = text.slice(found, found + query.length);
      fragment.appendChild(mark);
      start = found + query.length;
      found = comparable.indexOf(needle, start);
    }
    if (start < text.length) fragment.appendChild(document.createTextNode(text.slice(start)));
    textNode.replaceWith(fragment);
  });
  window.nexoraMatches = Array.prototype.slice.call(
    root.querySelectorAll('mark[data-nexora-find]')
  );
  window.nexoraPostMessage({ type: 'find', count: window.nexoraMatches.length });
  window.nexoraActivate(requestedIndex, shouldScroll);
};

window.nexoraScrollTo = function(anchor) {
  var target = document.getElementById(anchor);
  if (!target) return;
  target.scrollIntoView({ behavior: 'smooth', block: 'start', inline: 'nearest' });
};

document.addEventListener('click', function(event) {
  var image = event.target.closest('img');
  if (image) {
    event.preventDefault();
    window.nexoraPostMessage({ type: 'image', src: image.currentSrc || image.getAttribute('src') || '' });
    return;
  }
  var link = event.target.closest('a');
  if (!link) return;
  var href = link.getAttribute('href');
  if (!href) return;
  event.preventDefault();
  window.nexoraPostMessage({ type: 'link', href: href });
});

window.nexoraAttachEditor();
''';
