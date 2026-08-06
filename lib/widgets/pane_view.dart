import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../state/app_controller.dart';
import '../state/editor_session.dart';
import 'code_editor_view.dart';
import 'html_preview.dart';
import 'image_preview.dart';
import 'markdown_dom_preview.dart';
import 'markdown_preview.dart';
import 'outline_sidebar.dart';
import 'ui_primitives.dart';

/// Renders a single pane: a [CodeEditorView] for edit mode, a preview surface
/// (image / html / markdown) for preview mode, or both side-by-side for split
/// mode. Extracted from `DocumentArea` so each leaf of the split tree can host
/// its own view-mode switcher without needing to know about the split layout.
///
/// For markdown documents, also embeds an [OutlinePanel] on the right when the
/// global outline toggle ([AppController.showOutline]) is on — this keeps the
/// outline attached to the pane showing the document rather than floating at
/// the workspace edge.
class PaneView extends StatelessWidget {
  const PaneView({required this.controller, required this.session, super.key});

  final AppController controller;
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final doc = session.document;
    final canPreview = doc.isMarkdown || doc.isHtml || doc.isImage;
    final showDockedOutline =
        doc.isMarkdown && controller.showOutline && !controller.isSplit;
    if (!canPreview || session.viewMode == MarkdownViewMode.edit) {
      return KeyedSubtree(
        key: ValueKey('${doc.path}:edit'),
        child: _withOutline(_editor(), showDockedOutline),
      );
    }
    if (session.viewMode == MarkdownViewMode.preview) {
      return KeyedSubtree(
        key: const ValueKey('document-preview'),
        child: _withOutline(_preview(), showDockedOutline),
      );
    }
    return KeyedSubtree(
      key: ValueKey('${doc.path}:split'),
      child: _withOutline(
        _SplitMarkdownPane(controller: controller, session: session),
        showDockedOutline,
      ),
    );
  }

  /// Wraps [body] with an optional outline sidebar on the right. No-op when
  /// [showOutline] is false or the document isn't markdown.
  Widget _withOutline(Widget body, bool showOutline) {
    if (!showOutline) return body;
    return Row(
      children: [
        Expanded(child: body),
        SignalDivider(vertical: true),
        SizedBox(
          width: 240,
          child: OutlinePanel(controller: controller, session: session),
        ),
      ],
    );
  }

  Widget _editor() {
    return CodeEditorView(
      path: session.document.path,
      controller: session.editorController,
      findController: session.findController,
      scrollController: session.scrollController,
      initialScrollOffset: session.editorScrollOffset,
      wordWrap: session.wordWrap,
      fontScale: controller.fontScale,
      onChanged: (_) {},
      onSave: controller.saveActiveDocument,
    );
  }

  Widget _preview() {
    final workspace = controller.activeWorkspace;
    final workspaceRoot = workspace?.isDirectory == true
        ? workspace!.path
        : p.dirname(session.document.path);
    if (session.document.isImage) {
      return ImagePreview(path: session.document.path);
    }
    if (session.document.isHtml) {
      return HtmlPreview(
        path: session.document.path,
        content: session.document.content,
      );
    }
    if (Platform.isLinux) {
      return MarkdownPreview(
        path: session.document.path,
        workspaceRoot: workspaceRoot,
        content: session.document.content,
        headings: session.headings,
        previewAnchor: session.previewAnchor,
        previewJumpId: session.previewJumpId,
        findController: session.previewFindController,
        onPreviewJumpConsumed: (path, requestId) {
          controller.sessions[path]?.consumePreviewJump(requestId);
        },
        onOpenLocalPath: controller.openPath,
        onOpenAnchor: (anchor) {
          for (final heading in session.headings) {
            if (heading.anchor == anchor) {
              controller.jumpToHeadingInSession(
                session,
                heading.lineNumber,
                heading.anchor,
              );
              break;
            }
          }
        },
      );
    }
    return MarkdownDomPreview(
      path: session.document.path,
      workspaceRoot: workspaceRoot,
      content: session.document.content,
      headings: session.headings,
      previewAnchor: session.previewAnchor,
      previewJumpId: session.previewJumpId,
      findController: session.previewFindController,
      themeMode: controller.themeMode,
      themeId: controller.currentThemeId,
      fontScale: controller.fontScale,
      scrollOffset: session.previewScrollOffset,
      // Persist by path, not by captured session — the scroll sync is async and
      // by the time it lands the mounted session may have switched to another
      // document. Resolving the session by path keeps the value on the right
      // document.
      onScrollPersist: (path, y) {
        final target = controller.sessions[path];
        if (target != null) target.setPreviewScrollOffset(y);
      },
      onPreviewJumpConsumed: (path, requestId) {
        controller.sessions[path]?.consumePreviewJump(requestId);
      },
      onContentChanged: (path, content) {
        controller.sessions[path]?.replaceContentFromPreview(content);
      },
      onOpenLocalPath: controller.openPath,
      onOpenAnchor: (anchor) {
        for (final heading in session.headings) {
          if (heading.anchor == anchor) {
            controller.jumpToHeadingInSession(
              session,
              heading.lineNumber,
              heading.anchor,
            );
            break;
          }
        }
      },
    );
  }
}

/// Split-mode layout for a single markdown document: editor on the left,
/// live preview on the right, a draggable divider between them, and two-way
/// scroll sync so scrolling either side moves the other to the same relative
/// position.
class _SplitMarkdownPane extends StatefulWidget {
  const _SplitMarkdownPane({required this.controller, required this.session});

  final AppController controller;
  final EditorSession session;

  @override
  State<_SplitMarkdownPane> createState() => _SplitMarkdownPaneState();
}

class _SplitMarkdownPaneState extends State<_SplitMarkdownPane> {
  /// Fraction difference below which the two sides count as already aligned.
  /// Guards against feedback loops: when the preview echoes back the position
  /// we just drove it to (or the editor is already at the position the preview
  /// reported), syncing again would ping-pong forever.
  static const double _syncThreshold = 0.005;

  /// Editor scroll events fire at frame rate; the preview only needs to follow
  /// at ~25fps, and each sync drives a WebView JS round-trip plus a rebuild of
  /// this subtree. Throttling keeps the editor scrolling smooth.
  static const Duration _editorSyncInterval = Duration(milliseconds: 40);

  /// After we drive the preview from the editor, the preview echoes a scroll
  /// report back ~80-160ms later (80ms JS throttle + bridge latency). Treating
  /// that echo as a user scroll and reverse-syncing would yank the editor back
  /// mid-scroll. Reports arriving within this window are ignored for reverse
  /// sync.
  static const Duration _previewEchoWindow = Duration(milliseconds: 200);

  late double _ratio;
  double _reportedPreviewFraction = 0;
  DateTime _lastEditorDrive = DateTime.fromMillisecondsSinceEpoch(0);

  /// Drives the preview on the editor→preview direction. A [ValueNotifier]
  /// (instead of setState) so scrolling the editor never rebuilds this subtree
  /// — rebuilding re_editor's [CodeEditor] on every scroll is what made the
  /// editor feel janky.
  final ValueNotifier<double?> _previewFraction = ValueNotifier<double?>(null);

  EditorSession get _session => widget.session;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ratio = _session.splitRatio;
    _session.scrollController.verticalScroller.addListener(_onEditorScroll);
  }

  @override
  void dispose() {
    _session.scrollController.verticalScroller.removeListener(_onEditorScroll);
    _previewFraction.dispose();
    super.dispose();
  }

  void _onEditorScroll() {
    final scroller = _session.scrollController.verticalScroller;
    if (!scroller.hasClients) return;
    final max = scroller.position.maxScrollExtent;
    if (max <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastEditorDrive) < _editorSyncInterval) return;
    final fraction = (scroller.offset / max).clamp(0.0, 1.0);
    if ((fraction - _reportedPreviewFraction).abs() < _syncThreshold) return;
    if (_previewFraction.value == fraction) return;
    _lastEditorDrive = now;
    _previewFraction.value = fraction;
  }

  void _onPreviewFraction(double fraction) {
    _reportedPreviewFraction = fraction;
    // The preview just echoed back a position we drove it to — don't reverse
    // sync, or the editor gets yanked back while the user is still scrolling.
    if (DateTime.now().difference(_lastEditorDrive) < _previewEchoWindow) {
      return;
    }
    final scroller = _session.scrollController.verticalScroller;
    if (!scroller.hasClients) return;
    final max = scroller.position.maxScrollExtent;
    if (max <= 0) return;
    if ((scroller.offset / max - fraction).abs() < _syncThreshold) return;
    scroller.jumpTo((fraction * max).clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final editorWidth = totalWidth * _ratio;
        return Row(
          children: [
            SizedBox(width: editorWidth, child: _editor()),
            _divider(totalWidth),
            Expanded(child: _preview()),
          ],
        );
      },
    );
  }

  Widget _divider(double totalWidth) {
    final safeWidth = totalWidth <= 0 ? 1.0 : totalWidth;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final next = (_ratio + details.delta.dx / safeWidth).clamp(
            0.25,
            0.75,
          );
          if (next == _ratio) return;
          setState(() => _ratio = next);
          _session.setSplitRatio(next);
        },
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(
              width: 1,
              color: AppColors.signal.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    return CodeEditorView(
      path: _session.document.path,
      controller: _session.editorController,
      findController: _session.findController,
      scrollController: _session.scrollController,
      initialScrollOffset: _session.editorScrollOffset,
      wordWrap: _session.wordWrap,
      fontScale: _controller.fontScale,
      onChanged: (_) {},
      onSave: _controller.saveActiveDocument,
    );
  }

  Widget _preview() {
    final workspace = _controller.activeWorkspace;
    final workspaceRoot = workspace?.isDirectory == true
        ? workspace!.path
        : p.dirname(_session.document.path);
    if (_session.document.isImage) {
      return ImagePreview(path: _session.document.path);
    }
    if (_session.document.isHtml) {
      return HtmlPreview(
        path: _session.document.path,
        content: _session.document.content,
      );
    }
    if (Platform.isLinux) {
      return MarkdownPreview(
        path: _session.document.path,
        workspaceRoot: workspaceRoot,
        content: _session.document.content,
        headings: _session.headings,
        previewAnchor: _session.previewAnchor,
        previewJumpId: _session.previewJumpId,
        findController: _session.previewFindController,
        onPreviewJumpConsumed: (path, requestId) {
          _controller.sessions[path]?.consumePreviewJump(requestId);
        },
        onOpenLocalPath: _controller.openPath,
        onOpenAnchor: (anchor) {
          for (final heading in _session.headings) {
            if (heading.anchor == anchor) {
              _controller.jumpToHeadingInSession(
                _session,
                heading.lineNumber,
                heading.anchor,
              );
              break;
            }
          }
        },
      );
    }
    return MarkdownDomPreview(
      path: _session.document.path,
      workspaceRoot: workspaceRoot,
      content: _session.document.content,
      headings: _session.headings,
      previewAnchor: _session.previewAnchor,
      previewJumpId: _session.previewJumpId,
      findController: _session.previewFindController,
      themeMode: _controller.themeMode,
      themeId: _controller.currentThemeId,
      fontScale: _controller.fontScale,
      scrollOffset: _session.previewScrollOffset,
      // Persist by path, not by captured session — the scroll sync is async and
      // by the time it lands the mounted session may have switched to another
      // document. Resolving the session by path keeps the value on the right
      // document.
      onScrollPersist: (path, y) {
        final target = _controller.sessions[path];
        if (target != null) target.setPreviewScrollOffset(y);
      },
      onPreviewJumpConsumed: (path, requestId) {
        _controller.sessions[path]?.consumePreviewJump(requestId);
      },
      onScrollFractionChanged: _onPreviewFraction,
      scrollFraction: _previewFraction,
      onContentChanged: (path, content) {
        _controller.sessions[path]?.replaceContentFromPreview(content);
      },
      onOpenLocalPath: _controller.openPath,
      onOpenAnchor: (anchor) {
        for (final heading in _session.headings) {
          if (heading.anchor == anchor) {
            _controller.jumpToHeadingInSession(
              _session,
              heading.lineNumber,
              heading.anchor,
            );
            break;
          }
        }
      },
    );
  }
}
