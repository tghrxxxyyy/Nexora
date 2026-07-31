import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../state/app_controller.dart';
import '../state/editor_session.dart';
import 'code_editor_view.dart';
import 'html_preview.dart';
import 'markdown_dom_preview.dart';
import 'markdown_preview.dart';
import 'ui_primitives.dart';

class DocumentToolbar extends StatelessWidget {
  const DocumentToolbar({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.activeSession;
    final documentPaths = controller.activeDocumentPaths;
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.backgroundRaised),
      child: Row(
        children: [
          Expanded(
            child: documentPaths.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    itemCount: documentPaths.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final path = documentPaths[index];
                      final itemSession = controller.sessions[path];
                      if (itemSession == null) return const SizedBox.shrink();
                      return _DocumentTab(
                        name: itemSession.document.name,
                        dirty: itemSession.document.isDirty,
                        selected: session?.document.path == path,
                        onSelect: () => controller.selectDocument(path),
                        onClose: () => _closeDocument(
                          context,
                          controller,
                          path,
                          itemSession.document.isDirty,
                        ),
                      );
                    },
                  ),
          ),
          if (session != null) ...[
            AppIconButton(
              icon: Icons.undo_rounded,
              tooltip: '撤销',
              size: 30,
              iconSize: 16,
              onPressed: session.editorController.canUndo
                  ? session.editorController.undo
                  : null,
            ),
            AppIconButton(
              icon: Icons.redo_rounded,
              tooltip: '重做',
              size: 30,
              iconSize: 16,
              onPressed: session.editorController.canRedo
                  ? session.editorController.redo
                  : null,
            ),
            AppIconButton(
              icon: Icons.save_outlined,
              tooltip: '保存',
              selected: session.document.isDirty,
              accent: AppColors.signal,
              size: 30,
              iconSize: 16,
              onPressed: session.document.isDirty
                  ? controller.saveActiveDocument
                  : null,
            ),
            const SizedBox(width: 5),
            if (session.document.isMarkdown || session.document.isHtml)
              _ViewModeControl(session: session),
            if (session.document.isHtml)
              AppIconButton(
                icon: Icons.open_in_browser_rounded,
                tooltip: '在 Chrome 中打开',
                size: 30,
                iconSize: 16,
                onPressed: controller.openActiveHtmlInChrome,
              ),
            const SizedBox(width: 5),
            AppIconButton(
              icon: Icons.wrap_text_rounded,
              tooltip: '自动换行',
              selected: session.wordWrap,
              size: 30,
              iconSize: 16,
              onPressed: session.toggleWordWrap,
            ),
            if (session.document.isMarkdown)
              AppIconButton(
                icon: controller.rightCollapsed
                    ? Icons.toc_rounded
                    : Icons.last_page_rounded,
                tooltip: controller.rightCollapsed ? '展开目录' : '收起目录',
                selected: !controller.rightCollapsed,
                size: 30,
                iconSize: 16,
                onPressed: controller.toggleRightSidebar,
              ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Future<void> _closeDocument(
    BuildContext context,
    AppController controller,
    String path,
    bool dirty,
  ) async {
    if (!dirty) {
      controller.closeDocument(path, force: true);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭未保存文件'),
        content: Text('${p.basename(path)} 的修改尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (discard == true) controller.closeDocument(path, force: true);
  }
}

class DocumentArea extends StatelessWidget {
  const DocumentArea({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.activeWorkspace;
    final session = controller.activeSession;
    if (workspace == null) {
      return _LaunchSurface(controller: controller);
    }
    if (session == null) {
      return _WorkspaceIdle(
        name: workspace.name,
        isDirectory: workspace.isDirectory,
      );
    }

    return Column(
      children: [
        if (session.externallyChanged || session.deletedOnDisk)
          _ConflictBanner(controller: controller, session: session),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: AppMotion.standard,
              switchInCurve: AppMotion.curve,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [...previousChildren, ?currentChild],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.012, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _buildMode(session),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMode(EditorSession session) {
    final canPreview = session.document.isMarkdown || session.document.isHtml;
    if (!canPreview || session.viewMode == MarkdownViewMode.edit) {
      return KeyedSubtree(
        key: ValueKey('${session.document.path}:edit'),
        child: _editor(session),
      );
    }
    if (session.viewMode == MarkdownViewMode.preview) {
      return KeyedSubtree(
        key: const ValueKey('document-preview'),
        child: _preview(session),
      );
    }
    return KeyedSubtree(
      key: ValueKey('${session.document.path}:split'),
      child: Row(
        children: [
          Expanded(flex: 11, child: _editor(session)),
          const SignalDivider(vertical: true),
          Expanded(flex: 10, child: _preview(session)),
        ],
      ),
    );
  }

  Widget _editor(EditorSession session) {
    return CodeEditorView(
      path: session.document.path,
      controller: session.editorController,
      findController: session.findController,
      wordWrap: session.wordWrap,
      onChanged: (_) {},
    );
  }

  Widget _preview(EditorSession session) {
    if (session.document.isHtml) {
      return HtmlPreview(
        path: session.document.path,
        content: session.document.content,
      );
    }
    // Linux has no embedded WebView implementation in this app. Windows uses
    // WebView2 inside MarkdownDomPreview, keeping its editable DOM behavior
    // aligned with macOS.
    if (Platform.isLinux) {
      return MarkdownPreview(
        path: session.document.path,
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
      content: session.document.content,
      headings: session.headings,
      previewAnchor: session.previewAnchor,
      previewJumpId: session.previewJumpId,
      findController: session.previewFindController,
      themeMode: controller.themeMode,
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

class _ViewModeControl extends StatelessWidget {
  const _ViewModeControl({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeItem(
            label: '编辑',
            icon: Icons.edit_outlined,
            selected: session.viewMode == MarkdownViewMode.edit,
            onTap: () => session.setViewMode(MarkdownViewMode.edit),
          ),
          _ModeItem(
            label: '分屏',
            icon: Icons.vertical_split_outlined,
            selected: session.viewMode == MarkdownViewMode.split,
            onTap: () => session.setViewMode(MarkdownViewMode.split),
          ),
          _ModeItem(
            label: '预览',
            icon: Icons.visibility_outlined,
            selected: session.viewMode == MarkdownViewMode.preview,
            onTap: () => session.setViewMode(MarkdownViewMode.preview),
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  const _ModeItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: AnimatedContainer(
        duration: AppMotion.quick,
        width: 54,
        height: 24,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.signal.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected ? AppColors.signal : AppColors.textDim,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.text : AppColors.textDim,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab({
    required this.name,
    required this.dirty,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final String name;
  final bool dirty;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          width: 142,
          height: 30,
          padding: const EdgeInsets.only(left: 9, right: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.signal.withValues(alpha: 0.075)
                : _hovered
                ? AppColors.signal.withValues(alpha: 0.03)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (widget.dirty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Icon(
                  Icons.description_outlined,
                  size: 12,
                  color: AppColors.textDim,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.selected
                        ? AppColors.text
                        : AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ),
              if (_hovered || widget.selected)
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭文件',
                  size: 23,
                  iconSize: 12,
                  onPressed: widget.onClose,
                )
              else
                const SizedBox(width: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.controller, required this.session});

  final AppController controller;
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final deleted = session.deletedOnDisk;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.coral.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            deleted ? Icons.link_off_rounded : Icons.sync_problem_rounded,
            size: 16,
            color: AppColors.coral,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              deleted ? '磁盘文件已被删除' : '磁盘版本与当前编辑内容冲突',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 11),
            ),
          ),
          if (!deleted)
            TextButton(
              onPressed: controller.reloadActiveDocument,
              child: const Text('载入磁盘'),
            ),
          TextButton(
            onPressed: () => controller.saveActiveDocument(overwrite: true),
            child: Text(deleted ? '重新保存' : '覆盖保存'),
          ),
        ],
      ),
    );
  }
}

class _LaunchSurface extends StatelessWidget {
  const _LaunchSurface({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/x-file-icon-1024.png',
            width: 116,
            height: 116,
          ),
          const SizedBox(height: 22),
          Text(
            'x-file',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 33,
              fontWeight: FontWeight.w300,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TechButton(
                label: '打开文件',
                icon: Icons.insert_drive_file_outlined,
                onPressed: controller.openFiles,
              ),
              const SizedBox(width: 10),
              TechButton(
                label: '打开文件夹',
                icon: Icons.folder_open_rounded,
                primary: true,
                onPressed: controller.openDirectories,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceIdle extends StatelessWidget {
  const _WorkspaceIdle({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDirectory
                ? Icons.folder_open_rounded
                : Icons.description_outlined,
            size: 48,
            color: AppColors.signalDim,
          ),
          const SizedBox(height: 14),
          Text(
            name,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
