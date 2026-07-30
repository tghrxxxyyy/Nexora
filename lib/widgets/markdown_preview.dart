import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/markdown_heading.dart';
import '../state/preview_find_controller.dart';
import 'preview_find_panel.dart';

class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    required this.path,
    required this.content,
    required this.headings,
    required this.previewAnchor,
    required this.previewJumpId,
    required this.findController,
    this.onOpenLocalPath,
    this.onOpenAnchor,
    super.key,
  });

  final String path;
  final String content;
  final List<MarkdownHeading> headings;
  final String? previewAnchor;
  final int previewJumpId;
  final PreviewFindController findController;
  final ValueChanged<String>? onOpenLocalPath;
  final ValueChanged<String>? onOpenAnchor;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  final Map<String, GlobalKey> _headingKeys = {};
  final ValueNotifier<List<_PreviewTextMatch>> _searchMatches = ValueNotifier(
    const [],
  );
  bool _searchRefreshScheduled = false;
  bool _focusAfterSearchRefresh = false;
  int _observedFocusRequestId = 0;
  int _observedNavigationRequestId = 0;

  @override
  void initState() {
    super.initState();
    _syncHeadingKeys();
    _observedFocusRequestId = widget.findController.focusRequestId;
    _observedNavigationRequestId = widget.findController.navigationRequestId;
    widget.findController.addListener(_handleFindChanged);
    _scheduleSearchRefresh();
  }

  @override
  void didUpdateWidget(MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHeadingKeys();
    if (widget.findController != oldWidget.findController) {
      oldWidget.findController.removeListener(_handleFindChanged);
      _observedFocusRequestId = widget.findController.focusRequestId;
      _observedNavigationRequestId = widget.findController.navigationRequestId;
      widget.findController.addListener(_handleFindChanged);
    }
    if (widget.previewJumpId != oldWidget.previewJumpId) {
      final anchor = widget.previewAnchor;
      final requestId = widget.previewJumpId;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToHeading(anchor, requestId),
      );
    }
    if (widget.content != oldWidget.content ||
        widget.headings != oldWidget.headings ||
        widget.findController != oldWidget.findController) {
      _scheduleSearchRefresh();
    }
  }

  @override
  void dispose() {
    widget.findController.removeListener(_handleFindChanged);
    _searchMatches.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final baseText = textTheme.bodyLarge!.copyWith(
      color: AppColors.text,
      fontSize: 15,
      height: 1.72,
    );
    final behavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false, overscroll: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundRaised,
            AppColors.surface.withValues(alpha: 0.76),
            AppColors.backgroundRaised,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _SearchHighlightPainter(
                controller: _scrollController,
                findController: widget.findController,
                matches: _searchMatches,
              ),
            ),
          ),
          Scrollbar(
            controller: _scrollController,
            interactive: true,
            child: ScrollConfiguration(
              behavior: behavior,
              child: SingleChildScrollView(
                key: _viewportKey,
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  key: _contentKey,
                  padding: const EdgeInsets.fromLTRB(46, 36, 46, 90),
                  child: SelectionArea(
                    child: MarkdownBody(
                      key: ValueKey(widget.path),
                      data: widget.content,
                      selectable: false,
                      builders: _headingBuilders(),
                      styleSheet: MarkdownStyleSheet(
                        p: baseText,
                        pPadding: const EdgeInsets.only(bottom: 8),
                        a: baseText.copyWith(
                          color: AppColors.signal,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.signalDim,
                        ),
                        h1: TextStyle(
                          color: AppColors.text,
                          fontSize: 31,
                          fontWeight: FontWeight.w300,
                          height: 1.35,
                        ),
                        h1Padding: const EdgeInsets.only(top: 10, bottom: 14),
                        h2: TextStyle(
                          color: AppColors.text,
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                        h2Padding: const EdgeInsets.only(top: 22, bottom: 10),
                        h3: TextStyle(
                          color: AppColors.acid,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                        h3Padding: const EdgeInsets.only(top: 18, bottom: 8),
                        h4: TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        h5: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        h6: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        em: baseText.copyWith(fontStyle: FontStyle.italic),
                        strong: baseText.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                        code: TextStyle(
                          color: AppColors.acid,
                          backgroundColor: AppColors.surfaceRaised,
                          fontFamily: 'MapleMonoCN',
                          fontFamilyFallback: const ['monospace'],
                          fontSize: 13,
                          height: 1.55,
                        ),
                        codeblockPadding: const EdgeInsets.all(18),
                        codeblockDecoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        blockquote: baseText.copyWith(
                          color: AppColors.textMuted,
                        ),
                        blockquotePadding: const EdgeInsets.fromLTRB(
                          16,
                          10,
                          16,
                          10,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            left: BorderSide(color: AppColors.signal, width: 3),
                          ),
                        ),
                        listBullet: baseText.copyWith(color: AppColors.signal),
                        tableHead: baseText.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                        tableBody: baseText.copyWith(fontSize: 13),
                        tableBorder: TableBorder.all(color: AppColors.line),
                        tableCellsPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.lineStrong),
                          ),
                        ),
                        blockSpacing: 12,
                      ),
                      imageBuilder: (uri, title, alt) {
                        if (uri.hasScheme) {
                          return Image.network(
                            uri.toString(),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                _ImageError(alt: alt),
                          );
                        }
                        final imagePath = p.normalize(
                          p.join(p.dirname(widget.path), uri.toString()),
                        );
                        return Image.file(
                          File(imagePath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _ImageError(alt: alt),
                        );
                      },
                      onTapLink: (text, href, title) {
                        if (href == null || href.isEmpty) return;
                        if (href.startsWith('#')) {
                          widget.onOpenAnchor?.call(href.substring(1));
                          return;
                        }
                        final uri = Uri.tryParse(href);
                        if (uri != null && uri.hasScheme) {
                          _openExternal(uri.toString());
                          return;
                        }
                        final localPath = p.normalize(
                          p.join(p.dirname(widget.path), href.split('#').first),
                        );
                        widget.onOpenLocalPath?.call(localPath);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: ListenableBuilder(
              listenable: widget.findController,
              builder: (context, child) {
                return AnimatedSwitcher(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, MarkdownElementBuilder> _headingBuilders() {
    final registry = _HeadingAnchorRegistry(widget.headings, _headingKeys);
    return {
      for (final level in [1, 2, 3, 4, 5, 6])
        'h$level': _HeadingAnchorBuilder(registry, level),
    };
  }

  void _syncHeadingKeys() {
    final anchors = widget.headings.map((heading) => heading.anchor).toSet();
    _headingKeys.removeWhere((anchor, key) => !anchors.contains(anchor));
    for (final anchor in anchors) {
      _headingKeys.putIfAbsent(anchor, GlobalKey.new);
    }
  }

  void _jumpToHeading(String? anchor, int requestId, [int attempt = 0]) {
    if (!mounted || requestId != widget.previewJumpId || anchor == null) return;
    final target = _headingKeys[anchor]?.currentContext;
    final viewport = _viewportKey.currentContext;
    if (target == null || viewport == null || !_scrollController.hasClients) {
      if (attempt < 1) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToHeading(anchor, requestId, attempt + 1),
        );
      }
      return;
    }
    final targetBox = target.findRenderObject();
    final viewportBox = viewport.findRenderObject();
    if (targetBox is! RenderBox || viewportBox is! RenderBox) return;
    final targetOffset =
        targetBox.localToGlobal(Offset.zero).dy -
        viewportBox.localToGlobal(Offset.zero).dy +
        _scrollController.position.pixels;
    _animateToOffset(targetOffset - 10);
  }

  void _handleFindChanged() {
    final findController = widget.findController;
    final focusRequested =
        findController.focusRequestId != _observedFocusRequestId;
    final navigationRequested =
        findController.navigationRequestId != _observedNavigationRequestId;
    _observedFocusRequestId = findController.focusRequestId;
    _observedNavigationRequestId = findController.navigationRequestId;
    if (focusRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !findController.isOpen) return;
        findController.focusNode.requestFocus();
        findController.queryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: findController.query.length,
        );
      });
    }
    _scheduleSearchRefresh(focusActiveMatch: navigationRequested);
  }

  void _scheduleSearchRefresh({bool focusActiveMatch = false}) {
    _focusAfterSearchRefresh = _focusAfterSearchRefresh || focusActiveMatch;
    if (_searchRefreshScheduled) return;
    _searchRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchRefreshScheduled = false;
      _refreshSearchMatches();
    });
  }

  void _refreshSearchMatches() {
    if (!mounted) return;
    final findController = widget.findController;
    if (!findController.isOpen || findController.query.isEmpty) {
      _searchMatches.value = const [];
      findController.updateMatchCount(0);
      _focusAfterSearchRefresh = false;
      return;
    }
    final contentRoot = _contentKey.currentContext?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (contentRoot == null ||
        viewport is! RenderBox ||
        !_scrollController.hasClients) {
      _scheduleSearchRefresh(focusActiveMatch: _focusAfterSearchRefresh);
      return;
    }
    final viewportOrigin = viewport.localToGlobal(Offset.zero);
    final contentOffset = _scrollController.position.pixels;
    final expression = RegExp(
      RegExp.escape(findController.query),
      caseSensitive: findController.caseSensitive,
    );
    final matches = <_PreviewTextMatch>[];
    _visitRenderObjects(contentRoot, (renderObject) {
      if (renderObject is! RenderParagraph) return;
      final text = renderObject.text.toPlainText();
      if (text.isEmpty) return;
      final paragraphOrigin = renderObject.localToGlobal(Offset.zero);
      for (final match in expression.allMatches(text)) {
        final boxes = renderObject.getBoxesForSelection(
          TextSelection(baseOffset: match.start, extentOffset: match.end),
        );
        if (boxes.isEmpty) continue;
        final rects = boxes
            .map(
              (box) =>
                  Rect.fromLTRB(box.left, box.top, box.right, box.bottom).shift(
                    Offset(
                      paragraphOrigin.dx - viewportOrigin.dx,
                      paragraphOrigin.dy - viewportOrigin.dy + contentOffset,
                    ),
                  ),
            )
            .toList(growable: false);
        matches.add(_PreviewTextMatch(rects));
      }
    });
    matches.sort((left, right) {
      final vertical = left.bounds.top.compareTo(right.bounds.top);
      return vertical == 0
          ? left.bounds.left.compareTo(right.bounds.left)
          : vertical;
    });
    _searchMatches.value = List.unmodifiable(matches);
    findController.updateMatchCount(matches.length);
    if (_focusAfterSearchRefresh) {
      _focusAfterSearchRefresh = false;
      _scrollToActiveSearchMatch();
    }
  }

  void _visitRenderObjects(
    RenderObject root,
    ValueChanged<RenderObject> visitor,
  ) {
    visitor(root);
    root.visitChildren((child) => _visitRenderObjects(child, visitor));
  }

  void _scrollToActiveSearchMatch() {
    final index = widget.findController.activeIndex;
    final matches = _searchMatches.value;
    if (index < 0 || index >= matches.length || !_scrollController.hasClients) {
      return;
    }
    final viewportHeight =
        _viewportKey.currentContext?.size?.height ??
        _scrollController.position.viewportDimension;
    _animateToOffset(matches[index].bounds.top - viewportHeight * 0.2);
  }

  void _animateToOffset(double targetOffset) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final destination = targetOffset
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    final distance = (destination - position.pixels).abs();
    if (distance < 1) return;
    final milliseconds = math
        .min(720, math.max(240, 180 + math.sqrt(distance) * 17))
        .round();
    _scrollController.animateTo(
      destination,
      duration: Duration(milliseconds: milliseconds),
      curve: AppMotion.navigationCurve,
    );
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
}

class _HeadingAnchorRegistry {
  _HeadingAnchorRegistry(this.headings, this.keys);

  final List<MarkdownHeading> headings;
  final Map<String, GlobalKey> keys;
  int _index = 0;

  GlobalKey? next() {
    if (_index >= headings.length) return null;
    return keys[headings[_index++].anchor];
  }
}

class _HeadingAnchorBuilder extends MarkdownElementBuilder {
  _HeadingAnchorBuilder(this.registry, this.level);

  final _HeadingAnchorRegistry registry;
  final int level;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final key = registry.next();
    return Container(
      key: key,
      padding: switch (level) {
        1 => const EdgeInsets.only(top: 10, bottom: 14),
        2 => const EdgeInsets.only(top: 22, bottom: 10),
        3 => const EdgeInsets.only(top: 18, bottom: 8),
        _ => const EdgeInsets.only(top: 14, bottom: 7),
      },
      child: Text(element.textContent, style: preferredStyle),
    );
  }
}

class _PreviewTextMatch {
  _PreviewTextMatch(this.rects)
    : bounds = rects.reduce((value, element) => value.expandToInclude(element));

  final List<Rect> rects;
  final Rect bounds;
}

class _SearchHighlightPainter extends CustomPainter {
  _SearchHighlightPainter({
    required this.controller,
    required this.findController,
    required this.matches,
  }) : super(repaint: Listenable.merge([controller, findController, matches]));

  final ScrollController controller;
  final PreviewFindController findController;
  final ValueNotifier<List<_PreviewTextMatch>> matches;

  @override
  void paint(Canvas canvas, Size size) {
    if (!findController.isOpen ||
        findController.query.isEmpty ||
        !controller.hasClients) {
      return;
    }
    final offset = controller.position.pixels;
    final normalPaint = Paint()
      ..color = AppColors.amber.withValues(alpha: 0.25);
    final activePaint = Paint()
      ..color = AppColors.signal.withValues(alpha: 0.31);
    final activeBorder = Paint()
      ..color = AppColors.signal.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var index = 0; index < matches.value.length; index++) {
      final match = matches.value[index];
      final active = index == findController.activeIndex;
      for (final contentRect in match.rects) {
        final rect = contentRect.shift(Offset(0, -offset)).inflate(1.4);
        if (rect.bottom < 0 || rect.top > size.height) continue;
        final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        canvas.drawRRect(rounded, active ? activePaint : normalPaint);
        if (active) canvas.drawRRect(rounded, activeBorder);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SearchHighlightPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.findController != findController ||
        oldDelegate.matches != matches;
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: AppColors.textDim),
          if (alt != null && alt!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(alt!, style: TextStyle(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
