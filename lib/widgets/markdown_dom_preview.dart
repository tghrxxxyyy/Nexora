import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../models/markdown_heading.dart';
import '../services/markdown_asset_resolver.dart';
import '../services/markdown_code_highlighter.dart';
import '../services/mermaid_bundle.dart';
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
    required this.themeId,
    required this.fontScale,
    this.scrollOffset = 0,
    this.onScrollPersist,
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
  final String themeId;
  final double fontScale;

  /// Restore value applied after this document's DOM is (re)rendered. Fed from
  /// the owning session's saved scroll so switching back to a document lands
  /// where the reader left off.
  final double scrollOffset;

  /// Called right before this widget swaps the DOM to another document (or
  /// tears the WebView down for a theme refresh) so the outgoing document's
  /// scroll position can be persisted against its own session — keyed by
  /// [path], never the currently mounted session.
  final void Function(String path, double y)? onScrollPersist;

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
  String? _mermaidScript;
  int _observedFocusRequestId = 0;

  /// Path of the document currently rendered inside the WebView. Tracks the
  /// outgoing document right before the DOM is swapped, so we can read its
  /// `window.scrollY` and persist it to the right session.
  String? _currentPath;

  static const _appearanceChannel =
      MethodChannel('com.xuyu.nexora/webview_appearance');
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
    _currentPath = widget.path;
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
      // The DOM already reflects the user's contenteditable edit — the
      // markdown → HTML pipeline doesn't get to re-run on raw text edits,
      // so markdown syntax (e.g. **bold**) stays literal until the document
      // is reloaded. Re-rendering here would replace innerHTML on every
      // keystroke and fight contenteditable for the caret, which manifests
      // as the cursor jumping while typing. We accept the literal-text
      // trade-off rather than racing the user's input.
      _pendingPreviewContent = null;
      unawaited(_updateHeadingAnchors());
    } else if (widget.themeId != oldWidget.themeId ||
        widget.themeMode != oldWidget.themeMode) {
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
      _mermaidScript ??= await MermaidBundle.script();
    } catch (error, stack) {
      debugPrint('MermaidBundle.script failed: $error\n$stack');
      _mermaidScript = null;
    }
    try {
      final baseUrl = _resolveBaseUrl();
      await _controller.loadHtmlString(_documentHtml(), baseUrl: baseUrl);
    } catch (error, stack) {
      debugPrint('loadHtmlString failed for ${widget.path}: $error\n$stack');
      if (mounted) setState(() => _error = error.toString());
    }
    _pushAppearanceColor();
  }

  /// Tells the native side to repaint the NSWindow background and every
  /// WKWebView's `underPageBackgroundColor` with the current theme color.
  /// Without this, a 1px white seam leaks through on the right edge of the
  /// markdown preview in dark theme (the WKWebView default white bleeds
  /// through the gap between HTML body and WebView frame).
  ///
  /// The call is fired twice: once immediately (covers the case where the
  /// WebView was already attached from a previous load) and once after the
  /// next frame (covers first-mount, when the platform view is still being
  /// inserted into the NSView hierarchy at the time loadHtmlString returns).
  void _pushAppearanceColor() {
    if (!Platform.isMacOS) return;
    final argb = AppColors.background.toARGB32();
    final args = <String, dynamic>{
      'r': ((argb >> 16) & 0xff) / 255.0,
      'g': ((argb >> 8) & 0xff) / 255.0,
      'b': (argb & 0xff) / 255.0,
      'a': ((argb >> 24) & 0xff) / 255.0,
    };
    _appearanceChannel.invokeMethod<bool>('setBaseColor', args).catchError((_) => false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appearanceChannel.invokeMethod<bool>('setBaseColor', args).catchError((_) => false);
    });
  }

  /// Builds the WebView base URL pointing at the Markdown file's directory.
  ///
  /// Falls back to manual percent-encoding when `Uri.directory` rejects the
  /// path (e.g. paths containing a stray `%` like `50%off.md`).
  String _resolveBaseUrl() {
    final dirPath = '${p.dirname(widget.path)}${Platform.pathSeparator}';
    try {
      return Uri.directory(dirPath).toString();
    } catch (_) {
      final encoded = dirPath
          .split(Platform.pathSeparator)
          .map((segment) => segment.isEmpty ? '' : Uri.encodeComponent(segment))
          .join('/');
      return 'file://$encoded';
    }
  }

  /// Persists the currently rendered document's `window.scrollY` to its own
  /// session before the DOM is swapped out or the WebView is torn down. Reads
  /// [path]-keyed (not the mounted widget's path) so the value lands on the
  /// outgoing document's session.
  Future<void> _persistCurrentScroll() async {
    final outgoingPath = _currentPath;
    if (!_pageReady || outgoingPath == null) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        'window.scrollY',
      );
      final value = double.tryParse('$raw');
      if (value != null && value > 0) {
        widget.onScrollPersist?.call(outgoingPath, value);
      }
    } catch (_) {}
  }

  Future<void> _refreshThemedDocument() async {
    await _persistCurrentScroll();
    await _loadContent();
  }

  Future<void> _replaceDocument({bool preserveCursor = false}) async {
    if (!_pageReady) {
      await _loadContent();
      return;
    }
    await _persistCurrentScroll();
    _currentPath = widget.path;
    final baseUrl = _resolveBaseUrl();
    await _runJavaScript(
      'window.nexoraReplaceDocument('
      '${jsonEncode(_markdownHtml())}, ${jsonEncode(baseUrl)}, ${preserveCursor}, '
      '${widget.scrollOffset}'
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
    } else if (widget.scrollOffset > 0) {
      await _runJavaScript('window.nexoraSetScrollY(${widget.scrollOffset});');
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
      if (type == 'image-edit') {
        unawaited(_showImageEditDialog(value));
        return;
      }
      if (type == 'mermaid-edit') {
        unawaited(_showMermaidEditDialog(value));
        return;
      }
      final href = value['href'];
      if (type == 'link' && href is String) _openLink(href);
    } catch (_) {}
  }

  Future<void> _showImageEditDialog(Map<dynamic, dynamic> data) async {
    final src = (data['src'] as String?) ?? '';
    final altController =
        TextEditingController(text: (data['alt'] as String?) ?? '');
    final titleController =
        TextEditingController(text: (data['title'] as String?) ?? '');
    final widthController =
        TextEditingController(text: (data['width'] as String?) ?? '');
    final heightController =
        TextEditingController(text: (data['height'] as String?) ?? '');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑图片'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: altController,
                decoration: const InputDecoration(
                  labelText: '替代文本 (caption)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '标题 (title)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widthController,
                      decoration: const InputDecoration(labelText: '宽度'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: heightController,
                      decoration: const InputDecoration(labelText: '高度'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );

    if (accepted != true) return;
    await _runJavaScript(
      'window.nexoraUpdateImage(${jsonEncode(src)}, ${jsonEncode({
        'alt': altController.text,
        'title': titleController.text,
        'width': widthController.text,
        'height': heightController.text,
      })});',
    );
  }

  Future<void> _showMermaidEditDialog(Map<dynamic, dynamic> data) async {
    final sourceController = TextEditingController(
      text: (data['source'] as String?) ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑 Mermaid 源码'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: sourceController,
            decoration: const InputDecoration(
              labelText: 'Mermaid 源码',
              alignLabelWithHint: true,
            ),
            style: const TextStyle(
              fontFamily: 'MapleMonoCN',
              fontSize: 13,
              height: 1.5,
            ),
            maxLines: 18,
            minLines: 8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _runJavaScript(
      'window.nexoraUpdateMermaid(${jsonEncode(sourceController.text)});',
    );
  }

  void _openLink(String href) {
    final decodedHref = _safeDecode(href);
    if (decodedHref.startsWith('#')) {
      final anchor = _resolveAnchor(
        _safeDecodeComponent(decodedHref.substring(1)),
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
    final decodedSource = _safeDecode(source);
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

  /// Uri.decodeFull throws on stray `%`. Fall back to the raw input so a
  /// malformed href/src never blocks link/image handling.
  String _safeDecode(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  String _safeDecodeComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
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
    final baseUrl = _resolveBaseUrl();
    final dark = widget.themeMode == AppThemeMode.dark;
    final mermaidInit = _mermaidScript == null
        ? ''
        : '<script>$_mermaidScript</script>\n'
            '<script>if(window.mermaid){window.mermaid.initialize({'
            'startOnLoad:false,'
            "theme:'${dark ? 'dark' : 'default'}',"
            "securityLevel:'loose',"
            "fontFamily:'inherit'"
            '});}</script>';
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="${const HtmlEscape().convert(baseUrl)}">
<style>${_styleSheet()}</style>
$mermaidInit
</head>
<body>
<main id="nexora-document" contenteditable="true" spellcheck="false" tabindex="0">$markdownHtml</main>
<script>$_bridgeScript</script>
</body>
</html>''';
  }

  String _markdownHtml() {
    var source = widget.content;
    var frontMatterHtml = '';
    final fmMatch =
        RegExp(r'^---[ \t]*\n([\s\S]*?)\n---[ \t]*\n').firstMatch(source);
    if (fmMatch != null) {
      frontMatterHtml =
          '<pre class="nexora-front-matter"><code>${const HtmlEscape().convert(fmMatch.group(1)!)}</code></pre>';
      source = source.substring(fmMatch.end);
    }
    source = _expandImageSizes(source);
    final html = md.markdownToHtml(
      source,
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
    return frontMatterHtml +
        _codeHighlighter.decorate(_resolveLocalImageSources(anchoredHtml));
  }

  /// Expands `![alt](src =WxH)` sizing syntax into raw `<img>` HTML so the
  /// markdown package's inline-HTML path preserves width/height.
  String _expandImageSizes(String source) {
    final pattern = RegExp(
      r'!\[([^\]]*)\]\(\s*([^\s()]+)\s+=\s*(\d*)x?(\d*)\s*\)',
    );
    return source.replaceAllMapped(pattern, (match) {
      final alt = match.group(1)!;
      final src = match.group(2)!;
      final width = match.group(3);
      final height = match.group(4);
      final attrs = <String>[];
      if (width != null && width.isNotEmpty) attrs.add('width="$width"');
      if (height != null && height.isNotEmpty) attrs.add('height="$height"');
      final attrStr = attrs.isEmpty ? '' : ' ${attrs.join(' ')}';
      final escAlt =
          const HtmlEscape(HtmlEscapeMode.attribute).convert(alt);
      final escSrc =
          const HtmlEscape(HtmlEscapeMode.attribute).convert(src);
      return '<img alt="$escAlt" src="$escSrc"$attrStr />';
    });
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
:root {
  color-scheme: ${dark ? 'dark' : 'light'};
  --nexora-font-scale: ${widget.fontScale};
  --nx-element: ${_color(AppColors.signal)};
  --nx-element-deep: ${_color(dark ? AppColors.signal : AppColors.signalDim)};
  --nx-element-shallow: rgba(${_rgb(AppColors.signal)}, ${dark ? 0.55 : 0.45});
  --nx-element-so-shallow: rgba(${_rgb(AppColors.signal)}, ${dark ? 0.18 : 0.12});
  --nx-element-soo-shallow: rgba(${_rgb(AppColors.signal)}, ${dark ? 0.10 : 0.06});
  --nx-linecode: ${_color(dark ? AppColors.signal : AppColors.signalDim)};
  --nx-linecode-bg: rgba(${_rgb(AppColors.signal)}, ${dark ? 0.16 : 0.10});
  --nx-h2-fg: ${AppColors.signal.computeLuminance() > 0.55 ? '#1a1a1a' : '#fff'};
}
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
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", "PingFang SC", "Noto Sans CJK SC", monospace;
  font-size: calc(15px * var(--nexora-font-scale));
  line-height: 1.75;
  letter-spacing: 0;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
#nexora-document {
  width: min(100%, 950px);
  margin: 0 auto;
  padding: 30px 40px 96px;
  outline: none;
  caret-color: var(--nx-element);
  position: relative;
  z-index: 0;
  -webkit-user-select: text;
  user-select: text;
}
#nexora-document, #nexora-document * { -webkit-user-select: text; user-select: text; }
#nexora-document:focus { background: transparent; }

/* ===== Headings ===== */
#nexora-document h1,
#nexora-document h2,
#nexora-document h3,
#nexora-document h4,
#nexora-document h5,
#nexora-document h6 {
  scroll-margin-top: 28px;
  color: ${_color(AppColors.text)};
  position: relative;
  transition: color .3s ease, transform .3s ease;
}
#nexora-document h1 {
  text-align: center;
  font-size: calc(28px * var(--nexora-font-scale));
  font-weight: 700;
  margin: 14px auto 18px;
  line-height: 1.4;
  width: fit-content;
  min-width: 120px;
  padding-bottom: 12px;
  color: ${_color(AppColors.text)};
  border-bottom: none;
}
#nexora-document h1::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 50%;
  width: 50px;
  height: 4px;
  border-radius: 4px;
  background: linear-gradient(to right, var(--nx-element-deep), var(--nx-element), var(--nx-element-deep));
  background-size: 200% auto;
  transform: translateX(-50%);
  transition: width .4s cubic-bezier(.25, .8, .25, 1);
}
#nexora-document h1:hover { color: var(--nx-element); transform: translateY(-2px); }
#nexora-document h1:hover::after { width: 100%; }
#nexora-document h2 {
  color: var(--nx-h2-fg);
  font-size: calc(21px * var(--nexora-font-scale));
  line-height: 1.5;
  width: fit-content;
  max-width: 100%;
  font-weight: 700;
  margin: 24px 0 14px;
  padding: 6px 16px;
  border-radius: 8px;
  background: linear-gradient(to right, var(--nx-element-deep), var(--nx-element), var(--nx-element-deep));
  background-size: 200% auto;
  background-position: 0 center;
  box-shadow: 0 2px 6px rgba(${_rgb(AppColors.signal)}, ${dark ? 0.35 : 0.20});
  transition: background-position .5s ease-out, transform .4s ease, box-shadow .4s ease;
}
#nexora-document h2:hover {
  background-position: 100% center;
  transform: scale(1.01);
  box-shadow: 0 8px 20px rgba(${_rgb(AppColors.signal)}, ${dark ? 0.45 : 0.30});
}
#nexora-document h3 {
  position: relative;
  width: fit-content;
  max-width: 100%;
  margin: 22px 0 12px;
  text-align: left;
  font-size: calc(18px * var(--nexora-font-scale));
  font-weight: 700;
  color: ${_color(AppColors.text)};
  padding-left: 12px;
  transition: all .3s cubic-bezier(.25, .8, .25, 1);
}
#nexora-document h3::before {
  content: '';
  position: absolute;
  left: 0;
  top: 50%;
  transform: translateY(-50%);
  width: 5px;
  height: 65%;
  border-radius: 4px;
  background: var(--nx-element);
  transition: all .3s cubic-bezier(.25, .8, .25, 1);
}
#nexora-document h3:hover {
  padding-left: 18px;
  color: var(--nx-element);
}
#nexora-document h3:hover::before {
  height: 75%;
  width: 7px;
  background: var(--nx-element);
}
#nexora-document h4 {
  margin: 20px 0 10px;
  font-size: calc(16px * var(--nexora-font-scale));
  font-weight: 700;
  text-align: left;
  color: ${_color(AppColors.text)};
}
#nexora-document h4::before {
  content: '';
  margin-right: 8px;
  display: inline-block;
  background-color: var(--nx-element);
  width: 9px;
  height: 9px;
  border-radius: 100%;
  vertical-align: middle;
  transform: translateY(-2px);
  transition: all .3s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document h4:hover::before {
  transform: scale(1.4) translateY(-2px);
  box-shadow: 0 0 0 4px var(--nx-element-soo-shallow);
}
#nexora-document h5 {
  margin: 20px 0 10px;
  font-size: calc(14px * var(--nexora-font-scale));
  font-weight: 700;
  text-align: left;
  color: ${_color(AppColors.text)};
}
#nexora-document h5::before {
  content: '';
  margin-right: 8px;
  display: inline-block;
  background-color: ${_color(AppColors.backgroundRaised)};
  width: 10px;
  height: 10px;
  border-radius: 100%;
  border: 2px solid var(--nx-element);
  vertical-align: middle;
  transform: translateY(-2px);
  box-sizing: border-box;
  transition: all .3s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document h5:hover::before {
  background-color: var(--nx-element);
  transform: scale(1.2) translateY(-2px);
  box-shadow: 0 0 0 3px var(--nx-element-soo-shallow);
}
#nexora-document h6 {
  margin: 20px 0 10px;
  font-size: calc(13px * var(--nexora-font-scale));
  font-weight: 700;
  text-align: left;
  color: ${_color(AppColors.textMuted)};
}
#nexora-document h6::before {
  content: "—";
  color: var(--nx-element);
  margin-right: 8px;
  display: inline-block;
  vertical-align: middle;
  transition: transform .3s ease;
}
#nexora-document h6:hover::before {
  transform: scaleX(1.8) translateX(2px);
  font-weight: 700;
}
#nexora-document h4:hover,
#nexora-document h5:hover,
#nexora-document h6:hover {
  color: var(--nx-element-deep);
  transform: translateX(4px);
}

/* ===== Paragraphs & inline ===== */
#nexora-document p {
  margin: 8px 0;
  line-height: 1.85;
  color: ${_color(AppColors.text)};
}
#nexora-document a {
  color: ${_color(AppColors.text)};
  text-decoration: none;
  font-weight: 500;
  padding: 2px 4px;
  margin: 0 -2px;
  border-radius: 4px;
  background: 0 0;
  border-bottom: none;
  position: relative;
  transition: all .2s ease;
}
#nexora-document a::before {
  content: '';
  display: inline-block;
  width: 0.95em;
  height: 0.95em;
  margin-right: 4px;
  vertical-align: -.15em;
  background-color: var(--nx-element);
  -webkit-mask: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1024 1024'%3E%3Cpath d='M477.934459 330.486594A50.844091 50.844091 0 0 1 406.752731 258.796425L512 152.532274a254.220457 254.220457 0 0 1 359.467726 359.467726L762.66137 618.772592a50.844091 50.844091 0 1 1-71.690168-71.690169l106.772591-106.772592a152.532274 152.532274 0 0 0-215.578947-215.578947z m70.164846 361.501489A50.844091 50.844091 0 1 1 619.789474 762.66137l-107.281033 107.281033A254.220457 254.220457 0 0 1 152.532274 512L259.813307 406.752731a50.844091 50.844091 0 1 1 72.19861 69.656405l-107.789474 107.281033a152.532274 152.532274 0 0 0 215.578947 215.578947z m-126.601788-16.77855a50.844091 50.844091 0 1 1-71.690168-71.690169l251.678252-251.678252a50.844091 50.844091 0 0 1 71.690169 71.690169z'/%3E%3C/svg%3E") no-repeat center/contain;
  mask: url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1024 1024'%3E%3Cpath d='M477.934459 330.486594A50.844091 50.844091 0 0 1 406.752731 258.796425L512 152.532274a254.220457 254.220457 0 0 1 359.467726 359.467726L762.66137 618.772592a50.844091 50.844091 0 1 1-71.690168-71.690169l106.772591-106.772592a152.532274 152.532274 0 0 0-215.578947-215.578947z m70.164846 361.501489A50.844091 50.844091 0 1 1 619.789474 762.66137l-107.281033 107.281033A254.220457 254.220457 0 0 1 152.532274 512L259.813307 406.752731a50.844091 50.844091 0 1 1 72.19861 69.656405l-107.789474 107.281033a152.532274 152.532274 0 0 0 215.578947 215.578947z m-126.601788-16.77855a50.844091 50.844091 0 1 1-71.690168-71.690169l251.678252-251.678252a50.844091 50.844091 0 0 1 71.690169 71.690169z'/%3E%3C/svg%3E") no-repeat center/contain;
  transition: transform .4s cubic-bezier(.25, .8, .25, 1);
}
#nexora-document a:hover {
  color: var(--nx-element-deep);
  background: var(--nx-element-soo-shallow);
}
#nexora-document a:hover::before {
  transform: rotate(180deg);
  background-color: var(--nx-element-deep);
}
#nexora-document a:visited {
  color: var(--nx-element-deep);
}
/* Image-wrapping links (shields.io badges etc.): drop the link chrome */
#nexora-document a:has(> img) {
  padding: 0;
  margin: 0;
  background: none;
  border-radius: 0;
}
#nexora-document a:has(> img)::before { content: none; }
#nexora-document a:has(> img):hover { background: none; }
#nexora-document a:has(> img):hover::before { transform: none; }
#nexora-document strong {
  color: var(--nx-element);
  font-weight: 700;
  display: inline;
  position: relative;
  border-bottom: 2px solid transparent;
  -webkit-box-decoration-break: clone;
  box-decoration-break: clone;
  padding: 0 2px;
  transition: border-color .3s ease, color .3s ease, text-shadow .3s ease;
}
#nexora-document strong:hover {
  border-bottom-color: var(--nx-element-shallow);
  text-shadow: 0 2px 8px var(--nx-element-so-shallow);
}
#nexora-document em {
  font-style: italic;
  color: ${_color(AppColors.textMuted)};
  text-decoration: none !important;
  padding: 0 2px 1px;
  background-repeat: repeat-x;
  background-position: 0 100%;
  background-size: 6px 3px;
  background-image: linear-gradient(-45deg, transparent 35%, var(--nx-element-shallow) 35%, var(--nx-element-shallow) 65%, transparent 65%);
  -webkit-box-decoration-break: clone;
  box-decoration-break: clone;
  transition: color .2s ease, background-image .2s ease;
}
#nexora-document em:hover {
  color: var(--nx-element);
  background-image: linear-gradient(-45deg, transparent 35%, var(--nx-element) 35%, var(--nx-element) 65%, transparent 65%);
}
#nexora-document del {
  text-decoration: line-through;
  text-decoration-color: var(--nx-element);
  color: ${_color(AppColors.textDim)};
  transition: all .3s ease;
}
#nexora-document del:hover {
  opacity: .6;
  text-decoration-color: var(--nx-element-deep);
  cursor: not-allowed;
}
#nexora-document mark {
  background-color: transparent;
  color: inherit;
  padding: 0 2px;
  margin: 0;
  border-radius: 4px;
  font-weight: inherit;
  position: relative;
  -webkit-box-decoration-break: clone;
  box-decoration-break: clone;
  background-image: linear-gradient(to top, var(--nx-element-so-shallow), var(--nx-element-so-shallow));
  background-repeat: no-repeat;
  background-position: 0 100%;
  background-size: 100% 40%;
  transition: background-size .3s cubic-bezier(.34, 1.56, .64, 1), color .3s ease, border-radius .3s ease;
}
#nexora-document mark:hover {
  background-size: 100% 100%;
  border-radius: 6px;
}

/* ===== Code ===== */
#nexora-document code {
  color: var(--nx-linecode);
  background-color: var(--nx-linecode-bg);
  padding: 0.15em 0.4em;
  margin: 0 2px;
  border-radius: 4px;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: 0.9em;
  vertical-align: middle;
  word-break: break-word;
  transition: all .2s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document code:not(.hljs):hover {
  background-color: var(--nx-element);
  color: #fff;
  transform: scale(1.04);
  box-shadow: 0 4px 10px var(--nx-element-so-shallow);
}
pre {
  margin: 16px 0;
  overflow: auto;
  padding: 16px 18px;
  color: ${_color(AppColors.text)};
  background: ${_color(AppColors.surface)};
  border-radius: 6px;
}
#nexora-document pre code,
#nexora-document .nexora-code-block code {
  display: block;
  padding: 0;
  margin: 0;
  color: inherit;
  background: transparent;
  border-radius: 0;
  vertical-align: baseline;
  transition: none;
}
#nexora-document pre code:hover,
#nexora-document .nexora-code-block code:hover {
  background: transparent;
  color: inherit;
  transform: none;
  box-shadow: none;
}
.nexora-code-block {
  position: relative;
  margin: 18px 0;
  overflow: hidden;
  background: ${_color(AppColors.surface)};
  border: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.55 : 0.45});
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, ${dark ? 0.20 : 0.04});
}
.nexora-code-block::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 30px;
  background: rgba(${_rgb(AppColors.lineStrong)}, 0.30);
  border-bottom: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.50 : 0.40});
}
.nexora-code-block::after {
  content: '';
  position: absolute;
  top: 10px;
  left: 14px;
  width: 40px;
  height: 12px;
  background:
    radial-gradient(circle at 6px 6px, #ff5f56 4px, transparent 5px),
    radial-gradient(circle at 20px 6px, #ffbd2e 4px, transparent 5px),
    radial-gradient(circle at 34px 6px, #27c93f 4px, transparent 5px);
  pointer-events: none;
}
.nexora-code-block pre {
  margin: 0;
  padding: 40px 20px 18px;
  border-radius: 0;
  background: transparent;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: calc(13px * var(--nexora-font-scale));
  line-height: 1.7;
  tab-size: 2;
}
.nexora-code-language {
  position: absolute;
  z-index: 1;
  top: 7px;
  right: 12px;
  display: inline-flex;
  align-items: center;
  min-height: 16px;
  padding: 1px 8px;
  color: ${_color(AppColors.textMuted)};
  background: transparent;
  border: 0;
  border-radius: 999px;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", monospace;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.04em;
  line-height: 1.5;
  text-transform: lowercase;
  -webkit-user-select: none;
  user-select: none;
  pointer-events: none;
}
.hljs-comment, .hljs-quote { color: ${_color(AppColors.textDim)} !important; font-style: italic; }
.hljs-keyword, .hljs-selector-tag, .hljs-literal, .hljs-meta .hljs-keyword { color: ${_color(AppColors.coral)} !important; font-weight: 600; }
.hljs-string, .hljs-doctag, .hljs-regexp { color: ${_color(AppColors.acid)} !important; }
.hljs-number, .hljs-symbol, .hljs-bullet { color: ${_color(AppColors.amber)} !important; }
.hljs-title, .hljs-function, .hljs-title\.function_, .hljs-class .hljs-title { color: ${_color(AppColors.signal)} !important; font-weight: 600; }
.hljs-type, .hljs-built_in, .hljs-builtin-name { color: ${_color(AppColors.signalDim)} !important; }
.hljs-params, .hljs-variable, .hljs-template-variable { color: ${_color(AppColors.text)} !important; }
.hljs-attr, .hljs-attribute, .hljs-property { color: ${_color(AppColors.signalDim)} !important; }
.hljs-meta { color: ${_color(AppColors.textMuted)} !important; }
.hljs-tag, .hljs-name { color: ${_color(AppColors.coral)} !important; }
.hljs-selector-id, .hljs-selector-class { color: ${_color(AppColors.amber)} !important; }
.hljs-template-tag { color: ${_color(AppColors.signalDim)} !important; }
.hljs-link { color: ${_color(AppColors.signal)} !important; text-decoration: underline; }
.hljs-emphasis { font-style: italic; }
.hljs-strong { font-weight: 700; }
.hljs-addition { color: ${_color(AppColors.acid)} !important; }
.hljs-deletion { color: ${_color(AppColors.coral)} !important; }
kbd {
  display: inline-block;
  min-width: 1.6em;
  text-align: center;
  padding: 3px 6px;
  margin: 0 4px;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: .9em;
  line-height: 1.4;
  font-weight: 600;
  border-radius: 4px;
  background-color: ${_color(AppColors.backgroundRaised)};
  color: var(--nx-element-deep);
  border: 1px solid var(--nx-element);
  border-bottom-width: 3px;
  box-shadow: 0 2px 0 var(--nx-element-shallow);
  transition: all .15s cubic-bezier(.25, .8, .25, 1);
  transform: translateY(0);
}
kbd:hover {
  border-bottom-width: 1px;
  transform: translateY(2px);
  background-color: var(--nx-element-soo-shallow);
  box-shadow: 0 0 0 transparent;
  color: var(--nx-element-deep);
}

/* ===== Blockquote ===== */
#nexora-document blockquote {
  position: relative;
  margin: 20px 0;
  padding: 16px 20px 16px 48px;
  background-color: var(--nx-element-soo-shallow);
  border: none;
  border-radius: 12px;
  color: ${_color(AppColors.textMuted)};
  line-height: 1.7;
  transition: transform .3s cubic-bezier(.34, 1.56, .64, 1), background-color .3s ease;
}
#nexora-document blockquote::before {
  content: "✨";
  position: absolute;
  left: 16px;
  top: 16px;
  font-size: 18px;
  line-height: 1;
  font-family: "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", sans-serif;
}
#nexora-document blockquote p {
  color: ${_color(AppColors.textMuted)};
  margin-bottom: .5em;
}
#nexora-document blockquote p:last-child { margin-bottom: 0; }
#nexora-document blockquote:hover {
  transform: scale(1.01);
  background-color: var(--nx-element-so-shallow);
}
#nexora-document blockquote blockquote {
  margin: 10px 0;
  background-color: var(--nx-element-so-shallow);
  border-left: 3px solid var(--nx-element-shallow);
  border-radius: 8px;
}
#nexora-document blockquote blockquote::before {
  left: 12px;
  top: 12px;
  font-size: 15px;
}

/* GitHub-style callouts: > [!NOTE] / [!TIP] / [!WARNING] / [!IMPORTANT] / [!CAUTION] */
#nexora-document .nexora-alert {
  padding: 14px 18px;
  margin: 20px 0;
  color: ${_color(AppColors.text)};
  border: none;
  border-radius: 12px;
  position: relative;
  overflow: hidden;
  line-height: 1.7;
  transition: transform .3s cubic-bezier(.34, 1.56, .64, 1), box-shadow .3s ease, background-color .3s ease;
}
#nexora-document .nexora-alert::before { content: none; }
#nexora-document .nexora-alert p { color: inherit; margin-bottom: .5em; }
#nexora-document .nexora-alert p:last-child { margin-bottom: 0; }
#nexora-document .nexora-alert:hover {
  transform: scale(1.01) translateY(-2px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, ${dark ? 0.30 : 0.08});
}
#nexora-document .nexora-alert-text-container {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background-color: ${dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(255, 255, 255, 0.7)'};
  -webkit-backdrop-filter: blur(2px);
  backdrop-filter: blur(2px);
  padding: 2px 12px;
  border-radius: 50px;
  font-weight: 700;
  font-size: 14px;
  margin-bottom: 8px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.03);
  position: relative;
  z-index: 2;
}
#nexora-document .nexora-alert-icon {
  font-family: "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", sans-serif;
  font-size: 15px;
  line-height: 1;
}
#nexora-document .nexora-alert::after {
  content: "";
  position: absolute;
  right: -10px;
  bottom: -12px;
  font-family: "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", sans-serif;
  font-size: 64px;
  line-height: 1;
  opacity: .12;
  transform: rotate(-15deg);
  pointer-events: none;
  z-index: 0;
  transition: all .4s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document .nexora-alert:hover::after {
  transform: rotate(0) scale(1.1);
  opacity: .2;
  right: 0;
  bottom: -4px;
}
#nexora-document .nexora-alert-note { background-color: rgba(108, 92, 231, ${dark ? 0.18 : 0.10}); }
#nexora-document .nexora-alert-text-note { color: ${dark ? '#9b8cf0' : '#6c5ce7'}; }
#nexora-document .nexora-alert-note:hover { background-color: rgba(108, 92, 231, ${dark ? 0.24 : 0.15}); }
#nexora-document .nexora-alert-note::after { content: "📝"; }
#nexora-document .nexora-alert-tip { background-color: rgba(0, 184, 148, ${dark ? 0.18 : 0.10}); }
#nexora-document .nexora-alert-text-tip { color: ${dark ? '#3dd8bd' : '#00b894'}; }
#nexora-document .nexora-alert-tip:hover { background-color: rgba(0, 184, 148, ${dark ? 0.24 : 0.15}); }
#nexora-document .nexora-alert-tip::after { content: "💡"; }
#nexora-document .nexora-alert-warning { background-color: rgba(253, 203, 110, ${dark ? 0.20 : 0.15}); }
#nexora-document .nexora-alert-text-warning { color: ${dark ? '#f3a58c' : '#e17055'}; }
#nexora-document .nexora-alert-warning:hover { background-color: rgba(253, 203, 110, ${dark ? 0.26 : 0.20}); }
#nexora-document .nexora-alert-warning::after { content: "⚠️"; }
#nexora-document .nexora-alert-important { background-color: rgba(255, 118, 117, ${dark ? 0.20 : 0.12}); }
#nexora-document .nexora-alert-text-important { color: ${dark ? '#ff9b9a' : '#ff7675'}; }
#nexora-document .nexora-alert-important:hover { background-color: rgba(255, 118, 117, ${dark ? 0.28 : 0.18}); }
#nexora-document .nexora-alert-important::after { content: "📌"; }
#nexora-document .nexora-alert-caution { background-color: rgba(214, 48, 49, ${dark ? 0.16 : 0.08}); }
#nexora-document .nexora-alert-text-caution { color: ${dark ? '#ff5b5c' : '#d63031'}; }
#nexora-document .nexora-alert-caution:hover { background-color: rgba(214, 48, 49, ${dark ? 0.22 : 0.12}); }
#nexora-document .nexora-alert-caution::after { content: "🔥"; }

/* ===== Lists ===== */
#nexora-document ul, #nexora-document ol {
  margin-top: 4px;
  margin-left: 12px;
  margin-bottom: 10px;
  padding-left: 18px;
}
#nexora-document ul { list-style-type: disc; }
#nexora-document ul ul { list-style-type: circle; }
#nexora-document ul ul ul { list-style-type: square; }
#nexora-document ol { list-style-type: decimal; }
#nexora-document ol ol { list-style-type: lower-alpha; }
#nexora-document ol ol ol { list-style-type: lower-roman; }
#nexora-document li { margin: .3rem 0; }
#nexora-document li::marker { color: var(--nx-element-deep); }
#nexora-document li p { margin: 4px 0; }

/* ===== HR ===== */
#nexora-document hr {
  border: none;
  border-top: 3px dashed var(--nx-element-shallow);
  margin: 30px 0;
  opacity: .6;
  transform: scaleX(.85);
  transition: all .4s ease;
}
#nexora-document hr:hover {
  transform: scaleX(1);
  border-color: var(--nx-element);
  opacity: 1;
}

/* ===== Table ===== */
#nexora-document table {
  border-collapse: separate;
  border-spacing: 0;
  width: 100%;
  margin: 20px 0;
  border: 1px solid var(--nx-element-shallow);
  border-radius: 8px;
  overflow: hidden;
  font-size: 14px;
  line-height: 1.6;
}
#nexora-document table td,
#nexora-document table th {
  padding: 9px 13px;
  color: ${_color(AppColors.text)};
  border-right: 1px solid rgba(${_rgb(AppColors.line)}, ${dark ? 0.55 : 0.50});
  border-bottom: 1px solid rgba(${_rgb(AppColors.line)}, ${dark ? 0.55 : 0.50});
  transition: all .2s ease;
}
#nexora-document table td:last-child,
#nexora-document table th:last-child { border-right: none; }
#nexora-document table tr:last-child td { border-bottom: none; }
#nexora-document table th {
  background-color: var(--nx-element-soo-shallow);
  color: var(--nx-element-deep);
  font-weight: 700;
  white-space: nowrap;
}
#nexora-document table tbody tr { transition: background-color .2s ease; }
#nexora-document table tbody tr:nth-child(even) { background-color: var(--nx-element-soo-shallow); }
#nexora-document table tbody tr:hover { background-color: var(--nx-element-so-shallow); }
#nexora-document table tbody td:hover {
  background-color: var(--nx-element-soo-shallow);
  color: var(--nx-element-deep);
  box-shadow: inset 0 0 0 1px var(--nx-element-shallow);
}

/* ===== Image ===== */
#nexora-document img {
  border-radius: 10px;
  display: inline-block;
  margin: 14px 4px;
  object-fit: contain;
  max-width: 100%;
  height: auto;
  cursor: zoom-in;
  -webkit-user-drag: none;
  box-shadow: 0 4px 8px -2px rgba(0, 0, 0, ${dark ? 0.25 : 0.08});
  transition: all .4s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document p > img:only-child {
  display: block;
  margin: 18px auto;
}
#nexora-document img:hover {
  transform: scale(1.02);
  box-shadow: 0 12px 24px -4px var(--nx-element-so-shallow);
}
/* Inline images inside links (badges): tight, chrome-less, baseline aligned */
#nexora-document a > img {
  margin: 0 3px;
  border-radius: 3px;
  box-shadow: none;
  display: inline-block;
  vertical-align: middle;
  height: auto;
}
#nexora-document a > img:hover {
  transform: none;
  box-shadow: none;
}
#nexora-document figure {
  margin: 18px 0;
  text-align: center;
}
#nexora-document figure > img {
  display: block;
  margin: 0 auto;
}
#nexora-document figcaption {
  display: block;
  margin-top: 12px;
  font-size: 13px;
  color: ${_color(AppColors.textDim)};
  text-align: center;
  line-height: 1.5;
  transition: color .3s ease;
  -webkit-user-select: none;
  user-select: none;
}
#nexora-document figure:hover > figcaption {
  color: var(--nx-element-deep);
}

/* Mermaid diagrams */
#nexora-document .nexora-mermaid {
  margin: 20px 0;
  padding: 18px;
  text-align: center;
  background: ${_color(AppColors.surface)};
  border: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.45 : 0.35});
  border-radius: 8px;
  overflow-x: auto;
  position: relative;
}
#nexora-document .nexora-mermaid::before {
  content: "Mermaid";
  position: absolute;
  top: -8px;
  left: 14px;
  padding: 1px 7px;
  background: ${_color(AppColors.backgroundRaised)};
  color: ${_color(AppColors.signal)};
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.1em;
  border-radius: 3px;
  pointer-events: none;
}
#nexora-document .nexora-mermaid > .mermaid {
  min-height: 24px;
}
#nexora-document .nexora-mermaid svg {
  max-width: 100%;
  height: auto;
  display: inline-block;
}
#nexora-document .nexora-mermaid .node circle,
#nexora-document .nexora-mermaid .node ellipse,
#nexora-document .nexora-mermaid .node path,
#nexora-document .nexora-mermaid .node rect {
  fill: var(--nx-element-soo-shallow) !important;
  stroke: var(--nx-element) !important;
  stroke-width: 1.5px !important;
  transition: all .3s ease;
}
#nexora-document .nexora-mermaid .node polygon {
  fill: var(--nx-element-so-shallow) !important;
  stroke: var(--nx-element-deep) !important;
  stroke-width: 1.5px !important;
}
#nexora-document .nexora-mermaid .edgePath .path,
#nexora-document .nexora-mermaid .flowchart-link {
  stroke: var(--nx-element-deep) !important;
  stroke-width: 1.5px !important;
  opacity: .85 !important;
}
#nexora-document .nexora-mermaid .marker path,
#nexora-document .nexora-mermaid marker path {
  fill: var(--nx-element-deep) !important;
  stroke: var(--nx-element-deep) !important;
}
#nexora-document .nexora-mermaid .node .label,
#nexora-document .nexora-mermaid .edgeLabel,
#nexora-document .nexora-mermaid .cluster-label text {
  color: ${_color(AppColors.text)} !important;
  fill: ${_color(AppColors.text)} !important;
  font-weight: 500 !important;
}
#nexora-document .nexora-mermaid .edgeLabel .label,
#nexora-document .nexora-mermaid .edgeLabel rect {
  fill: ${_color(AppColors.backgroundRaised)} !important;
  background-color: ${_color(AppColors.backgroundRaised)} !important;
}
#nexora-document .nexora-mermaid .cluster rect {
  fill: var(--nx-element-soo-shallow) !important;
  stroke: var(--nx-element-shallow) !important;
  stroke-dasharray: 4px !important;
}
#nexora-document .nexora-mermaid .cluster span,
#nexora-document .nexora-mermaid .cluster-label text {
  fill: var(--nx-element-deep) !important;
  color: var(--nx-element-deep) !important;
  background: transparent !important;
  font-weight: 700 !important;
}
#nexora-document .nexora-mermaid .error {
  color: ${_color(AppColors.coral)} !important;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: 12px;
}

/* Footnotes (markdown package: sup.footnote-ref + section.footnotes) */
#nexora-document sup.footnote-ref {
  display: inline-block;
  font-size: 10px;
  font-weight: 700;
  vertical-align: super;
  line-height: 1;
  margin: 0 2px;
}
#nexora-document sup.footnote-ref > a {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border-radius: 999px;
  background: var(--nx-element-so-shallow);
  color: var(--nx-element-deep) !important;
  text-decoration: none;
  font-size: 10px;
  font-weight: 600;
  transition: all .2s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document sup.footnote-ref > a::before { content: none; }
#nexora-document sup.footnote-ref > a:hover {
  background: var(--nx-element);
  color: #fff !important;
  transform: translateY(-1px);
}
#nexora-document sup.footnote-ref > a:hover::before { transform: none; }
#nexora-document section.footnotes {
  margin: 28px 0 16px;
  padding: 16px 20px;
  background: var(--nx-element-soo-shallow);
  border: 1px solid var(--nx-element-shallow);
  border-radius: 8px;
  position: relative;
}
#nexora-document section.footnotes::before {
  content: "脚注";
  display: block;
  margin-bottom: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.40 : 0.30});
  color: ${_color(AppColors.textMuted)};
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.12em;
}
#nexora-document section.footnotes > ol {
  margin: 0;
  padding-left: 20px;
}
#nexora-document section.footnotes li {
  margin: 6px 0;
  color: ${_color(AppColors.textMuted)};
  line-height: 1.6;
}
#nexora-document section.footnotes li::marker { color: var(--nx-element-deep); }
#nexora-document section.footnotes a.footnote-backref {
  display: inline-block;
  font-size: 12px;
  color: var(--nx-element-deep);
  text-decoration: none;
  margin-left: 4px;
  transition: all .2s ease;
}
#nexora-document section.footnotes a.footnote-backref::before { content: none; }
#nexora-document section.footnotes a.footnote-backref:hover {
  color: var(--nx-element);
  transform: scale(1.2);
}

/* Task-list checkboxes: replace native macOS box with a custom one */
#nexora-document li:has(> input[type="checkbox"]) {
  list-style: none;
  padding-left: 2px;
}
#nexora-document input[type="checkbox"] {
  appearance: none;
  -webkit-appearance: none;
  width: 15px;
  height: 15px;
  margin: 0 7px 0 0;
  vertical-align: middle;
  position: relative;
  border: 1.5px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.85 : 0.65});
  border-radius: 4px;
  background: ${_color(AppColors.surfaceRaised)};
  cursor: default;
  transition: all .2s cubic-bezier(.34, 1.56, .64, 1);
}
#nexora-document input[type="checkbox"]:checked {
  background: ${_color(AppColors.signal)};
  border-color: ${_color(AppColors.signal)};
}
#nexora-document input[type="checkbox"]:checked::after {
  content: '';
  position: absolute;
  left: 3.5px;
  top: 0.5px;
  width: 4px;
  height: 8px;
  border: solid #fff;
  border-width: 0 2px 2px 0;
  transform: rotate(45deg);
}
#nexora-document li:has(> input[type="checkbox"]:checked) {
  color: ${_color(AppColors.textMuted)};
  text-decoration: line-through;
  text-decoration-color: rgba(${_rgb(AppColors.textMuted)}, 0.45);
}

/* YAML front matter */
#nexora-document .nexora-front-matter {
  margin: 18px 0;
  padding: 16px 20px;
  background: ${_color(AppColors.surface)};
  border: 1px dashed rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.65 : 0.50});
  border-radius: 8px;
  position: relative;
  overflow: auto;
}
#nexora-document .nexora-front-matter::before {
  content: "YAML";
  position: absolute;
  top: -8px;
  left: 14px;
  padding: 1px 7px;
  background: ${_color(AppColors.backgroundRaised)};
  color: ${_color(AppColors.signal)};
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.1em;
  border-radius: 3px;
}
#nexora-document .nexora-front-matter code {
  display: block;
  padding: 0;
  margin: 0;
  color: ${_color(AppColors.textMuted)};
  background: transparent;
  border-radius: 0;
  font-family: "Maple Mono", "MapleMonoCN", "SF Mono", Consolas, monospace;
  font-size: 12.5px;
  line-height: 1.7;
  vertical-align: baseline;
  transition: none;
}
#nexora-document .nexora-front-matter code:hover {
  background: transparent;
  color: ${_color(AppColors.textMuted)};
  transform: none;
  box-shadow: none;
}

/* [TOC] directory block */
#nexora-document .nexora-toc {
  margin: 20px 0;
  padding: 16px 20px;
  background: ${_color(AppColors.surface)};
  border: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.50 : 0.40});
  border-radius: 12px;
  position: relative;
}
#nexora-document .nexora-toc::before {
  content: "目录";
  display: block;
  margin-bottom: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid rgba(${_rgb(AppColors.lineStrong)}, ${dark ? 0.40 : 0.30});
  color: ${_color(AppColors.textMuted)};
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.12em;
}
#nexora-document .nexora-toc-item {
  display: block;
  padding: 4px 8px;
  margin: 0;
  color: ${_color(AppColors.textMuted)};
  text-decoration: none;
  border-radius: 4px;
  font-size: 13.5px;
  line-height: 1.5;
  transition: all .2s ease;
}
#nexora-document .nexora-toc-item::before { content: none; }
#nexora-document .nexora-toc-item:hover {
  background: var(--nx-element-soo-shallow);
  color: var(--nx-element);
}
#nexora-document .nexora-toc-item:hover::before { transform: none; }
#nexora-document .nexora-toc-level-2 { padding-left: 20px; }
#nexora-document .nexora-toc-level-3 { padding-left: 36px; }
#nexora-document .nexora-toc-level-4 { padding-left: 52px; }
#nexora-document .nexora-toc-level-5 { padding-left: 68px; }
#nexora-document .nexora-toc-level-6 { padding-left: 84px; }

/* ===== Find highlights ===== */
mark.nexora-find { color: inherit; background: rgba(${_rgb(AppColors.amber)}, 0.40); border-radius: 3px; padding: 0 1px; }
mark.nexora-find.nexora-find-active { background: rgba(${_rgb(AppColors.signal)}, 0.45); }
#nexora-document mark::before,
#nexora-document mark::after { content: none !important; display: none !important; }

/* ===== Scrollbar ===== */
::-webkit-scrollbar { width: 6px; height: 8px; }
::-webkit-scrollbar-track { background: transparent; border-radius: 10px; }
::-webkit-scrollbar-thumb {
  border-radius: 10px;
  background: var(--nx-element-shallow);
}
::-webkit-scrollbar-thumb:hover { background: var(--nx-element); }
::-webkit-scrollbar-thumb:active { background: var(--nx-element-deep); }

@media (max-width: 720px) {
  #nexora-document { padding: 22px 18px 72px; }
  #nexora-document h1 { font-size: 24px; }
  #nexora-document h2 { font-size: 19px; }
}

@media print {
  @page { margin: 10mm; size: A4; }
  html, body { background: #fff !important; min-height: auto; }
  #nexora-document {
    width: 100%;
    max-width: none;
    padding: 0;
    margin: 0;
  }
  #nexora-document h1,
  #nexora-document h2,
  #nexora-document h3,
  #nexora-document h4,
  #nexora-document h5,
  #nexora-document h6 {
    page-break-after: avoid;
    transform: none !important;
  }
  #nexora-document p { orphans: 2; widows: 2; }
  #nexora-document figure,
  #nexora-document pre,
  #nexora-document .nexora-code-block,
  #nexora-document table,
  #nexora-document blockquote,
  #nexora-document tr,
  #nexora-document img,
  #nexora-document li { page-break-inside: avoid; }
  #nexora-document .nexora-page-break { page-break-after: always; }
  * {
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
}
''';
  }

  String _color(Color color) =>
      '#${(color.toARGB32() & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';

  String _rgb(Color color) {
    final value = color.toARGB32();
    return '${(value >> 16) & 0xff}, ${(value >> 8) & 0xff}, ${value & 0xff}';
  }
}

const _bridgeScript = r'''
window.nexoraReady = function() {
  window.nexoraEnhanceAlerts();
  window.nexoraBuildToc();
  window.nexoraWrapImages();
  window.nexoraRenderMermaid();
};
window.nexoraSetFontScale = function(value) {
  document.documentElement.style.setProperty('--nexora-font-scale', value);
};
window.nexoraSetScrollY = function(y) {
  window.scrollTo({ top: y, behavior: 'instant' });
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

window.nexoraAlertMap = {
  NOTE: { type: 'note', title: 'Note', icon: '📝' },
  TIP: { type: 'tip', title: 'Tip', icon: '💡' },
  WARNING: { type: 'warning', title: 'Warning', icon: '⚠️' },
  IMPORTANT: { type: 'important', title: 'Important', icon: '📌' },
  CAUTION: { type: 'caution', title: 'Caution', icon: '🔥' }
};

window.nexoraEnhanceAlerts = function() {
  document.querySelectorAll('#nexora-document blockquote').forEach(function(bq) {
    if (bq.classList.contains('nexora-alert')) return;
    var target = bq.querySelector('p') || bq;
    var html = target.innerHTML || '';
    var match = html.match(/^\s*\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION)\]\s*(?:<br\s*\/?>|\n)?/i);
    if (!match) return;
    var item = window.nexoraAlertMap[match[1].toUpperCase()];
    if (!item) return;
    target.innerHTML = html.slice(match[0].length);
    var capsule = document.createElement('div');
    capsule.className = 'nexora-alert-text-container nexora-alert-text-' + item.type;
    capsule.setAttribute('contenteditable', 'false');
    capsule.innerHTML = '<span class="nexora-alert-icon">' + item.icon + '</span>' + item.title;
    bq.insertBefore(capsule, bq.firstChild);
    bq.classList.add('nexora-alert', 'nexora-alert-' + item.type);
  });
};

window.nexoraBuildToc = function() {
  var root = document.getElementById('nexora-document');
  if (!root) return;
  var placeholders = Array.prototype.slice.call(root.querySelectorAll('p'));
  placeholders.forEach(function(p) {
    if ((p.textContent || '').trim() !== '[TOC]') return;
    var headings = Array.prototype.slice.call(root.querySelectorAll('h1, h2, h3, h4, h5, h6'));
    var nav = document.createElement('nav');
    nav.className = 'nexora-toc';
    nav.setAttribute('contenteditable', 'false');
    headings.forEach(function(h) {
      var level = parseInt(h.tagName.substring(1), 10);
      var a = document.createElement('a');
      a.className = 'nexora-toc-item nexora-toc-level-' + level;
      a.href = '#' + (h.id || '');
      a.textContent = (h.textContent || '').replace(/\s+/g, ' ').trim();
      nav.appendChild(a);
    });
    p.replaceWith(nav);
  });
};

window.nexoraWrapImages = function() {
  document.querySelectorAll('#nexora-document img').forEach(function(img) {
    if (img.closest('figure')) return;
    if (img.closest('a')) return;
    var alt = (img.getAttribute('alt') || '').trim();
    var title = (img.getAttribute('title') || '').trim();
    var caption = alt || title;
    if (!caption) return;
    var parent = img.parentNode;
    var target = img;
    if (parent && parent.tagName === 'P') {
      var onlyChild = true;
      for (var i = 0; i < parent.childNodes.length; i++) {
        var n = parent.childNodes[i];
        if (n === img) continue;
        if (n.nodeType === Node.TEXT_NODE && ((n.nodeValue || '').trim() === '')) continue;
        onlyChild = false;
        break;
      }
      if (onlyChild) target = parent;
    }
    var figure = document.createElement('figure');
    figure.setAttribute('contenteditable', 'false');
    target.parentNode.replaceChild(figure, target);
    figure.appendChild(img);
    var figcaption = document.createElement('figcaption');
    figcaption.className = 'nexora-caption';
    figcaption.setAttribute('contenteditable', 'false');
    figcaption.textContent = caption;
    figure.appendChild(figcaption);
  });
};

window.nexoraUpdateImage = function(src, attrs) {
  var imgs = document.querySelectorAll('#nexora-document img');
  var img = null;
  for (var i = 0; i < imgs.length; i++) {
    if (imgs[i].getAttribute('src') === src) { img = imgs[i]; break; }
  }
  if (!img) return;
  ['alt', 'title', 'width', 'height'].forEach(function(key) {
    var v = attrs[key];
    if (v) img.setAttribute(key, v);
    else img.removeAttribute(key);
  });
  var figure = img.closest('figure');
  var caption = (img.getAttribute('alt') || img.getAttribute('title') || '').trim();
  if (figure) {
    var figcaption = figure.querySelector('figcaption');
    if (caption) {
      if (!figcaption) {
        figcaption = document.createElement('figcaption');
        figcaption.className = 'nexora-caption';
        figcaption.setAttribute('contenteditable', 'false');
        figure.appendChild(figcaption);
      }
      figcaption.textContent = caption;
    } else {
      if (figcaption) figcaption.remove();
      figure.replaceWith(img);
    }
  } else if (caption) {
    window.nexoraWrapImages();
  }
  window.nexoraSendContent();
};

window.nexoraRenderMermaid = function() {
  if (!window.mermaid) return;
  var containers = document.querySelectorAll('#nexora-document .nexora-mermaid');
  if (!containers.length) return;
  containers.forEach(function(container) {
    var source = container.dataset.nexoraMermaidSource || '';
    var target = container.querySelector('.mermaid');
    if (!target) {
      target = document.createElement('div');
      target.className = 'mermaid';
      container.appendChild(target);
    }
    target.removeAttribute('data-processed');
    target.innerHTML = source;
  });
  try {
    window.mermaid.run({
      nodes: document.querySelectorAll('#nexora-document .nexora-mermaid .mermaid')
    });
  } catch (error) {
    console.error('mermaid render failed:', error);
  }
};

window.nexoraUpdateMermaid = function(source) {
  var container = document.querySelector('#nexora-document .nexora-mermaid');
  if (!container) return;
  container.dataset.nexoraMermaidSource = source;
  window.nexoraRenderMermaid();
  window.nexoraSendContent();
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
      var checkbox = item.querySelector('input[type="checkbox"]');
      var checkboxMark = checkbox ? '[' + (checkbox.checked ? 'x' : ' ') + '] ' : '';
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
      var result = prefix + checkboxMark + body.trim();
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
    if (node.classList.contains('nexora-alert-text-container')) return '';
    if (node.classList.contains('nexora-mermaid')) {
      var mermaidSource = node.dataset.nexoraMermaidSource || '';
      return '```mermaid\n' +
          mermaidSource.replace(/^\n+|\n+$/g, '') +
          '\n```\n\n';
    }
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
    if (tag === 'sub') return '~' + value.trim() + '~';
    if (tag === 'sup') return '^' + value.trim() + '^';
    if (tag === 'pre' && node.classList.contains('nexora-front-matter')) {
      var yamlText = (node.textContent || '').replace(/^\n+|\n+$/g, '');
      return '---\n' + yamlText + '\n---\n\n';
    }
    if (tag === 'pre') {
      var code = node.querySelector('code');
      var className = (code && code.className) || '';
      var match = className.match(/(?:^|\s)language-([^\s]+)/);
      var language = match ? match[1] : '';
      return '```' + language + '\n' +
          (node.textContent || '').replace(/^\n+|\n+$/g, '') + '\n```\n\n';
    }
    if (tag === 'blockquote') {
      var alertMatch = (node.className || '').match(/nexora-alert-(note|tip|warning|important|caution)\b/);
      var lines = value.trim().split('\n');
      if (alertMatch) lines.unshift('[!' + alertMatch[1].toUpperCase() + ']');
      return lines.map(function(line) {
        return line ? '> ' + line : '>';
      }).join('\n') + '\n\n';
    }
    if (tag === 'ul' || tag === 'ol') return list(node, tag === 'ol');
    if (tag === 'table') return table(node);
    if (tag === 'hr') return '---\n\n';
    if (tag === 'nav' && node.classList.contains('nexora-toc')) return '[TOC]\n\n';
    if (tag === 'section' && node.classList.contains('footnotes')) {
      var ol = node.querySelector('ol');
      var items = ol ? Array.prototype.filter.call(ol.children, function(child) {
        return child.tagName === 'LI';
      }) : [];
      var lines = items.map(function(li) {
        var id = li.getAttribute('id') || '';
        var label = id.replace(/^fn-/i, '');
        var clone = li.cloneNode(true);
        Array.prototype.forEach.call(
          clone.querySelectorAll('a.footnote-backref, sup.footnote-ref'),
          function(el) { el.remove(); }
        );
        return '[^' + decodeURIComponent(label) + ']: ' + inlineChildren(clone).trim();
      });
      return lines.join('\n') + '\n\n';
    }
    if (tag === 'sup' && node.classList.contains('footnote-ref')) {
      var anchor = node.querySelector('a');
      var refHref = anchor ? (anchor.getAttribute('href') || '') : '';
      var refMatch = refHref.match(/fn-(.+)$/);
      if (refMatch) return '[^' + decodeURIComponent(refMatch[1]) + ']';
      return '';
    }
    if (tag === 'figure') return children(node);
    if (tag === 'figcaption') return '';
    if (tag === 'a') return '[' + value.trim() + '](' + (node.getAttribute('href') || '') + ')';
    if (tag === 'img') {
      var src = node.getAttribute('src') || '';
      var alt = node.getAttribute('alt') || '';
      var width = node.getAttribute('width') || '';
      var height = node.getAttribute('height') || '';
      var size = '';
      if (width && height) size = ' =' + width + 'x' + height;
      else if (width) size = ' =' + width;
      else if (height) size = ' =x' + height;
      return '![' + alt + '](' + src + size + ')';
    }
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

window.nexoraReplaceDocument = function(html, baseHref, preserveCursor, restoreY) {
  window.nexoraClearFind();
  var root = document.getElementById('nexora-document');
  if (!root) return;
  root.contentEditable = 'true';
  var savedScroll = window.scrollY;
  var savedContext = preserveCursor ? window.nexoraSaveSelectionContext() : null;
  root.innerHTML = html;
  var base = document.querySelector('base');
  if (base) base.href = baseHref;
  window.nexoraAttachEditor();
  window.nexoraEnhanceAlerts();
  window.nexoraBuildToc();
  window.nexoraWrapImages();
  window.nexoraRenderMermaid();
  if (preserveCursor) {
    window.nexoraRestoreSelectionContext(savedContext);
    window.scrollTo({ top: savedScroll, behavior: 'instant' });
  } else if (typeof restoreY === 'number' && restoreY > 0) {
    window.scrollTo({ top: restoreY, behavior: 'instant' });
  } else {
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
};

// Captures the cursor as (blockIndex, offsetWithinBlock) so it can be
// restored after the parent <main> does innerHTML replacement. Block index
// is the cursor's closest-direct-child index of #nexora-document — this
// survives re-render as long as the user's edit didn't add/remove a block.
window.nexoraSaveSelectionContext = function() {
  var root = document.getElementById('nexora-document');
  if (!root) return null;
  var selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return null;
  var range = selection.getRangeAt(0);
  var cursorNode = range.startContainer;
  if (!root.contains(cursorNode)) return null;
  var block = cursorNode;
  while (block && block.parentNode !== root) {
    block = block.parentNode;
  }
  if (!block || block.parentNode !== root) return null;
  var blockIndex = Array.prototype.indexOf.call(root.childNodes, block);
  if (blockIndex < 0) return null;
  var preRange = document.createRange();
  preRange.selectNodeContents(block);
  try {
    preRange.setEnd(range.startContainer, range.startOffset);
  } catch (_) {
    return null;
  }
  return { blockIndex: blockIndex, offset: preRange.toString().length };
};

// Restores a context captured by nexoraSaveSelectionContext. Falls back to
// the end of the same block (or end of document) when the exact offset no
// longer maps to a text node — which happens when markdown formatting
// changes the inline structure (e.g. ** → <strong>).
window.nexoraRestoreSelectionContext = function(ctx) {
  var root = document.getElementById('nexora-document');
  if (!root || !ctx) return;
  var block = root.childNodes[ctx.blockIndex];
  if (!block) block = root.lastChild;
  if (!block) return;
  var filter = {
    acceptNode: function(node) {
      var parent = node.parentNode;
      while (parent && parent !== block) {
        if (parent.contentEditable === 'false') {
          return NodeFilter.FILTER_REJECT;
        }
        parent = parent.parentNode;
      }
      return NodeFilter.FILTER_ACCEPT;
    }
  };
  var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, filter, null);
  var current = 0;
  var target = ctx.offset;
  var lastNode = null;
  var lastLen = 0;
  while (walker.nextNode()) {
    var textNode = walker.currentNode;
    var len = (textNode.nodeValue || '').length;
    lastNode = textNode;
    lastLen = len;
    if (current + len >= target) {
      try {
        var range = document.createRange();
        range.setStart(textNode, target - current);
        range.collapse(true);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      } catch (_) {}
      root.focus({ preventScroll: true });
      return;
    }
    current += len;
  }
  if (lastNode) {
    try {
      var endRange = document.createRange();
      endRange.setStart(lastNode, lastLen);
      endRange.collapse(true);
      var endSel = window.getSelection();
      endSel.removeAllRanges();
      endSel.addRange(endRange);
    } catch (_) {}
    root.focus({ preventScroll: true });
  }
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
    if (window.nexoraImageClickTimer) return;
    var src = image.currentSrc || image.getAttribute('src') || '';
    window.nexoraImageClickTimer = window.setTimeout(function() {
      window.nexoraImageClickTimer = null;
      window.nexoraPostMessage({ type: 'image', src: src });
    }, 220);
    return;
  }
  var link = event.target.closest('a');
  if (!link) return;
  var href = link.getAttribute('href');
  if (!href) return;
  event.preventDefault();
  window.nexoraPostMessage({ type: 'link', href: href });
});

document.addEventListener('dblclick', function(event) {
  var mermaidContainer = event.target.closest('.nexora-mermaid');
  if (mermaidContainer) {
    event.preventDefault();
    if (window.nexoraImageClickTimer) {
      window.clearTimeout(window.nexoraImageClickTimer);
      window.nexoraImageClickTimer = null;
    }
    window.nexoraPostMessage({
      type: 'mermaid-edit',
      source: mermaidContainer.dataset.nexoraMermaidSource || ''
    });
    return;
  }
  var image = event.target.closest('img');
  if (!image) return;
  event.preventDefault();
  if (window.nexoraImageClickTimer) {
    window.clearTimeout(window.nexoraImageClickTimer);
    window.nexoraImageClickTimer = null;
  }
  window.nexoraPostMessage({
    type: 'image-edit',
    src: image.getAttribute('src') || '',
    alt: image.getAttribute('alt') || '',
    title: image.getAttribute('title') || '',
    width: image.getAttribute('width') || '',
    height: image.getAttribute('height') || ''
  });
});

window.nexoraAttachEditor();
''';
