import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
  const PaneView({
    required this.controller,
    required this.session,
    super.key,
  });

  final AppController controller;
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final doc = session.document;
    final canPreview = doc.isMarkdown || doc.isHtml || doc.isImage;
    final showOutline = doc.isMarkdown && controller.showOutline;
    if (!canPreview || session.viewMode == MarkdownViewMode.edit) {
      return KeyedSubtree(
        key: ValueKey('${doc.path}:edit'),
        child: _withOutline(_editor(), showOutline),
      );
    }
    if (session.viewMode == MarkdownViewMode.preview) {
      return KeyedSubtree(
        key: const ValueKey('document-preview'),
        child: _withOutline(_preview(), showOutline),
      );
    }
    return KeyedSubtree(
      key: ValueKey('${doc.path}:split'),
      child: _withOutline(
        Row(
          children: [
            Expanded(flex: 11, child: _editor()),
            SignalDivider(vertical: true),
            Expanded(flex: 10, child: _preview()),
          ],
        ),
        showOutline,
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
      wordWrap: session.wordWrap,
      fontScale: controller.fontScale,
      onChanged: (_) {},
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
        onOpenLocalPath: controller.openPath,
        onOpenAnchor: (anchor) {
          for (final heading in session.headings) {
            if (heading.anchor == anchor) {
              controller.jumpToHeading(heading.lineNumber, heading.anchor);
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
      onContentChanged: session.replaceContentFromPreview,
      onOpenLocalPath: controller.openPath,
      onOpenAnchor: (anchor) {
        for (final heading in session.headings) {
          if (heading.anchor == anchor) {
            controller.jumpToHeading(heading.lineNumber, heading.anchor);
            break;
          }
        }
      },
    );
  }
}
