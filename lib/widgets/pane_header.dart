import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../services/file_icon_resolver.dart';
import '../state/app_controller.dart';
import '../utils/path_display.dart';
import 'drag_feedback.dart';
import 'outline_sidebar.dart';
import 'pane_drag_payload.dart';

/// Per-pane tab strip shown above each pane when the workspace is split.
/// Mirrors the file-tab chrome from [DocumentToolbar] but scoped to a single
/// pane's openPaths — clicking a tab activates it within the pane, closing a
/// tab removes it from the pane (and disposes the session if no other pane
/// references it).
class PaneHeader extends StatelessWidget {
  const PaneHeader({required this.controller, required this.paneId, super.key});

  final AppController controller;
  final String paneId;

  @override
  Widget build(BuildContext context) {
    final leaf = controller.paneLeaf(paneId);
    final paths = leaf?.openPaths ?? const <String>[];
    final activeIndex = leaf?.activeIndex ?? 0;
    final paneSession = controller.paneSessionFor(paneId);
    final showFloatingOutline =
        controller.isSplit && paneSession?.document.isMarkdown == true;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.backgroundRaised,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: paths.isEmpty
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) {
                final menuWidth = (constraints.maxWidth - 12)
                    .clamp(120.0, 270.0)
                    .toDouble();
                return Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        itemCount: paths.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 2),
                        itemBuilder: (context, index) {
                          final path = paths[index];
                          final session = controller.sessions[path];
                          final selected = index == activeIndex;
                          return _PaneTab(
                            path: path,
                            name: session?.document.name ?? p.basename(path),
                            dirty: session?.document.isDirty ?? false,
                            selected: selected,
                            canMoveRight: controller.canMoveDocumentToRightPane(
                              paneId,
                              path,
                            ),
                            onTap: () => controller.selectPaneTab(paneId, path),
                            onClose: () =>
                                controller.closePaneTab(paneId, path),
                            onMoveRight: () =>
                                controller.moveDocumentToRightPane(
                                  sourcePaneId: paneId,
                                  filePath: path,
                                ),
                          );
                        },
                      ),
                    ),
                    if (showFloatingOutline && paneSession != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: HoverOutlineMenu(
                          key: ValueKey(
                            '${paneSession.document.path}:outline-menu',
                          ),
                          controller: controller,
                          session: paneSession,
                          menuWidth: menuWidth,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _PaneTab extends StatefulWidget {
  const _PaneTab({
    required this.path,
    required this.name,
    required this.dirty,
    required this.selected,
    required this.canMoveRight,
    required this.onTap,
    required this.onClose,
    required this.onMoveRight,
  });

  final String path;
  final String name;
  final bool dirty;
  final bool selected;
  final bool canMoveRight;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Future<void> Function() onMoveRight;

  @override
  State<_PaneTab> createState() => _PaneTabState();
}

class _PaneTabState extends State<_PaneTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: truncatePathForDisplay(widget.path),
        waitDuration: const Duration(milliseconds: 100),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: _showContextMenu,
          child: AnimatedContainer(
            duration: AppMotion.quick,
            constraints: const BoxConstraints(maxWidth: 170),
            height: 26,
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.signal.withValues(alpha: 0.085)
                  : _hovered
                  ? AppColors.signal.withValues(alpha: 0.035)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PaneFileIcon(path: widget.path),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
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
                if (widget.dirty || _hovered || widget.selected) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      child: _DirtyAwareCloseIcon(
                        dirty: widget.dirty,
                        hovered: _hovered,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
    // Wrapping in Draggable lets the user grab any pane tab and drag it onto
    // another pane's edges (split) or center (open as a tab there). The
    // source pane keeps its tab — this is "copy to" not "move" semantics,
    // matching how sidebar file drags already behave.
    return Draggable<PaneDragPayload>(
      data: PaneDragPayload(filePath: widget.path),
      feedback: PaneDragFeedback(filePath: widget.path),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: content,
    );
  }

  /// Opens the tab context menu at the pointer location.
  ///
  /// Parameters:
  /// - [details]: secondary-click coordinates in global window space.
  Future<void> _showContextMenu(TapDownDetails details) async {
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (overlayBox is! RenderBox) return;
    final localPosition = overlayBox.globalToLocal(details.globalPosition);
    final action = await showMenu<_PaneTabAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlayBox.size.width - localPosition.dx,
        overlayBox.size.height - localPosition.dy,
      ),
      items: [
        PopupMenuItem<_PaneTabAction>(
          value: _PaneTabAction.moveRight,
          enabled: widget.canMoveRight,
          height: 34,
          child: Row(
            children: [
              Icon(
                Icons.vertical_split_rounded,
                size: 15,
                color: widget.canMoveRight
                    ? AppColors.textMuted
                    : AppColors.textDim,
              ),
              const SizedBox(width: 9),
              Text(
                '移动到右侧',
                style: TextStyle(
                  color: widget.canMoveRight
                      ? AppColors.text
                      : AppColors.textDim,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (mounted && action == _PaneTabAction.moveRight && widget.canMoveRight) {
      await widget.onMoveRight();
    }
  }
}

/// Actions exposed by an opened document tab's secondary-click menu.
enum _PaneTabAction { moveRight }

class _PaneFileIcon extends StatelessWidget {
  const _PaneFileIcon({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final visual = resolveFileVisual(
      FileIconContext(path: path, isDirectory: false),
    );
    if (visual.svgAssetKey != null) {
      return SvgPicture.asset(
        visual.svgAssetKey!,
        width: 13,
        height: 13,
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
/// editor-group tab behavior.
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

/// Convenience helper for callers that just need the basename of a path for
/// display in a pane header without re-deriving it.
String paneHeaderDisplayName(String path) => p.basename(path);

/// Used by callers (e.g. [SplitPaneHost]) that want to know whether a paneId
/// is still part of the active workspace's split tree.
bool paneExists(AppController controller, String paneId) {
  return controller.activeWorkspace?.split?.containsPane(paneId) ?? false;
}
