import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/split_layout.dart';
import '../models/workspace_item.dart';
import '../services/file_icon_resolver.dart';
import '../state/app_controller.dart';
import '../state/editor_session.dart';
import '../utils/path_display.dart';
import 'diff_view.dart';
import 'drag_feedback.dart';
import 'file_context_menu.dart';
import 'pane_drag_payload.dart';
import 'split_pane_host.dart';
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
      child: documentPaths.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 4,
              ),
              itemCount: documentPaths.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final path = documentPaths[index];
                final itemSession = controller.sessions[path];
                if (itemSession == null) return const SizedBox.shrink();
                return _DocumentTab(
                  path: path,
                  controller: controller,
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
    if (controller.gitActiveDiff != null) {
      return DiffView(controller: controller);
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
          child: ClipRect(child: _buildPaneSurface(workspace, session)),
        ),
      ],
    );
  }

  Widget _buildPaneSurface(WorkspaceItem workspace, EditorSession session) {
    final split = workspace.split;
    if (split != null) {
      return SplitPaneHost(controller: controller, node: split);
    }
    // No split yet — synthesize a single-leaf tree so the renderer treats the
    // unsplit case exactly like a one-pane split (per-pane tab strip and
    // drop-zone included). paneLeaf('root') in the controller falls back to
    // the workspace's open documents to populate the tab strip.
    return SplitPaneHost(
      controller: controller,
      node: SplitLeaf(paneId: 'root', openPaths: [session.document.path]),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab({
    required this.path,
    required this.controller,
    required this.name,
    required this.dirty,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final String path;
  final AppController controller;
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
  Timer? _tooltipHideTimer;

  @override
  void dispose() {
    _tooltipHideTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    setState(() => _hovered = true);
    _tooltipHideTimer?.cancel();
    _tooltipHideTimer = Timer(const Duration(seconds: 1), () {
      Tooltip.dismissAllToolTips();
    });
  }

  void _onHoverExit() {
    setState(() => _hovered = false);
    _tooltipHideTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Draggable<PaneDragPayload>(
      data: PaneDragPayload(filePath: widget.path),
      feedback: PaneDragFeedback(filePath: widget.path),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: Tooltip(
          message: truncatePathForDisplay(widget.path),
          waitDuration: const Duration(milliseconds: 100),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _onHoverEnter(),
            onExit: (_) => _onHoverExit(),
            child: SizedBox(
              width: 142,
              height: 30,
              child: Center(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: Tooltip(
        message: truncatePathForDisplay(widget.path),
        waitDuration: const Duration(milliseconds: 100),
        child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: GestureDetector(
          onTap: widget.onSelect,
        onSecondaryTapDown: (details) => showFileContextMenu(
          context: context,
          position: details.globalPosition,
          controller: widget.controller,
          path: widget.path,
          isDirectory: false,
        ),
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
              _TabFileIcon(path: widget.path),
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
              if (widget.dirty || _hovered || widget.selected)
                GestureDetector(
                  onTap: widget.onClose,
                  child: Tooltip(
                    message: widget.dirty
                        ? (_hovered ? '关闭并放弃修改' : '未保存')
                        : '关闭文件',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Container(
                      width: 23,
                      height: 23,
                      alignment: Alignment.center,
                      child: _DirtyAwareCloseIcon(
                        dirty: widget.dirty,
                        hovered: _hovered,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 23),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}

class _TabFileIcon extends StatelessWidget {
  const _TabFileIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final visual = resolveFileVisual(
      FileIconContext(path: path, isDirectory: false),
    );
    if (visual.svgAssetKey != null) {
      return SvgPicture.asset(
        visual.svgAssetKey!,
        width: 14,
        height: 14,
        colorFilter: visual.tintSvg && visual.color != null
            ? ColorFilter.mode(visual.color!, BlendMode.srcIn)
            : null,
      );
    }
    return Icon(
      visual.icon ?? Icons.description_outlined,
      size: 12,
      color: visual.color ?? AppColors.textDim,
    );
  }
}

/// Renders the close button as a • when the document is dirty (and not yet
/// hovered) so the user gets a visible "unsaved changes" cue. Switches to the
/// x icon on hover so the action is still discoverable. Matches VSCode's
/// editor-tab behavior.
class _DirtyAwareCloseIcon extends StatelessWidget {
  const _DirtyAwareCloseIcon({required this.dirty, required this.hovered});

  final bool dirty;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    if (dirty && !hovered) {
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          shape: BoxShape.circle,
        ),
      );
    }
    return Icon(
      Icons.close_rounded,
      size: 13,
      color: hovered ? AppColors.text : AppColors.textDim,
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
            'assets/icon/nexora-icon-1024.png',
            width: 116,
            height: 116,
          ),
          const SizedBox(height: 22),
          Text(
            'Nexora',
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
