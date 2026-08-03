import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/file_node.dart';
import '../models/markdown_heading.dart';
import '../services/file_icon_resolver.dart';
import '../state/app_controller.dart';
import '../utils/path_display.dart';
import 'drag_feedback.dart';
import 'file_context_menu.dart';
import 'pane_drag_payload.dart';
import 'ui_primitives.dart';

enum _TreeRowType { directory, file, heading }

class FileExplorerPanel extends StatefulWidget {
  const FileExplorerPanel({required this.controller, super.key});

  final AppController controller;

  @override
  State<FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<FileExplorerPanel> {
  final TextEditingController _filterController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _filter = '';
  int? _hoveredRowIndex;
  int _observedRevealRequestId = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant FileExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _observedRevealRequestId = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final controller = widget.controller;
    if (controller.revealRequestId != _observedRevealRequestId) {
      _observedRevealRequestId = controller.revealRequestId;
      WidgetsBinding.instance.addPostFrameCallback(_scrollToActiveFile);
    }
  }

  void _scrollToActiveFile(_) {
    if (!_scrollController.hasClients) return;
    final controller = widget.controller;
    final workspace = controller.activeWorkspace;
    final selectedPath = workspace?.selectedFilePath;
    if (selectedPath == null || workspace?.isDirectory != true) return;

    final rows = <_TreeRow>[];
    _flatten(controller, controller.childrenFor(workspace!.path), 0, rows);
    final filtered = _filter.isEmpty
        ? rows
        : _filterRows(rows, _filter.toLowerCase());
    var targetIndex = -1;
    for (var i = 0; i < filtered.length; i++) {
      if (filtered[i].node.path == selectedPath && !filtered[i].isHeading) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) return;

    const itemExtent = 30.0;
    final viewport = _scrollController.position.viewportDimension;
    final currentMin = _scrollController.offset;
    final currentMax = currentMin + viewport;
    final target = targetIndex * itemExtent;
    if (target >= currentMin && target + itemExtent <= currentMax) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final desiredOffset = (target - viewport / 2 + itemExtent / 2)
        .clamp(0.0, maxScroll)
        .toDouble();
    _scrollController.animateTo(
      desiredOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final workspace = controller.activeWorkspace;
    if (workspace?.isDirectory != true) return const SizedBox.shrink();
    final rows = <_TreeRow>[];
    _flatten(controller, controller.childrenFor(workspace!.path), 0, rows);
    final visibleRows = _filter.isEmpty
        ? rows
        : _filterRows(rows, _filter.toLowerCase());

    return PanelSurface(
      child: Column(
        children: [
          PanelLabel(
            label: workspace.name,
            trailing: AppIconButton(
              icon: Icons.refresh_rounded,
              tooltip: '刷新文件树',
              size: 27,
              iconSize: 14,
              onPressed: controller.busy
                  ? null
                  : controller.refreshActiveDirectory,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _filterController,
                textAlignVertical: TextAlignVertical.center,
                onChanged: (value) => setState(() => _filter = value.trim()),
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText: '筛选文件',
                  prefixIcon: const Icon(Icons.filter_alt_outlined, size: 14),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _filterController.clear();
                            setState(() => _filter = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 13),
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
          SignalDivider(),
          if (controller.busy)
            LinearProgressIndicator(
              minHeight: 1,
              color: AppColors.signal,
              backgroundColor: AppColors.surface,
            ),
          Expanded(
            child: visibleRows.isEmpty
                ? const _EmptyTree()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: visibleRows.length,
                    itemExtent: 30,
                    itemBuilder: (context, index) {
                      final hoveredIndex = _hoveredRowIndex;
                      return _FileRow(
                        row: visibleRows[index],
                        selectedPath: workspace.selectedFilePath,
                        hoverMode: widget.controller.fileTreeHoverMode,
                        hoverDistance: hoveredIndex == null
                            ? null
                            : (index - hoveredIndex).abs(),
                        onHoverChanged: (hovered) {
                          setState(() {
                            if (hovered) {
                              _hoveredRowIndex = index;
                            } else if (_hoveredRowIndex == index) {
                              _hoveredRowIndex = null;
                            }
                          });
                        },
                        onTap: () => _onRowTap(visibleRows[index]),
                        onArrowTap: () => _onArrowTap(visibleRows[index]),
                        onSecondaryTap: (position) =>
                            _showRowContextMenu(visibleRows[index], position),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _onRowTap(_TreeRow row) {
    final controller = widget.controller;
    if (row.isDirectory) {
      controller.toggleDirectory(row.node.path);
    } else if (row.isHeading) {
      final heading = row.heading!;
      controller.openAndJumpToHeading(
        row.node.path,
        heading.lineNumber,
        heading.anchor,
      );
    } else {
      controller.openDocument(row.node.path);
    }
  }

  void _onArrowTap(_TreeRow row) {
    if (row.isFile && _isMarkdown(row.node.name)) {
      widget.controller.toggleFileHeadings(row.node.path);
    }
  }

  void _showRowContextMenu(_TreeRow row, Offset position) {
    if (row.isHeading) return;
    showFileContextMenu(
      context: context,
      position: position,
      controller: widget.controller,
      path: row.node.path,
      isDirectory: row.isDirectory,
    );
  }

  static bool _isMarkdown(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  void _flatten(
    AppController controller,
    List<FileNode> nodes,
    int depth,
    List<_TreeRow> output,
  ) {
    for (final node in nodes) {
      var displayNode = node;
      final segments = <String>[node.name];
      if (node.isDirectory) {
        while (true) {
          final children = controller.childrenFor(displayNode.path);
          if (children.length != 1 || !children.single.isDirectory) break;
          displayNode = children.single;
          segments.add(displayNode.name);
        }
      }

      final expanded = controller.expandedDirectories.contains(
        displayNode.path,
      );

      if (displayNode.isFile) {
        final dirty =
            controller.sessions[displayNode.path]?.document.isDirty == true;
        output.add(
          _TreeRow(
            node: displayNode,
            displayName: segments.join('.'),
            depth: depth,
            expanded: controller.expandedFileHeadings.contains(
              displayNode.path,
            ),
            dirty: dirty,
          ),
        );

        if (_isMarkdown(displayNode.name) &&
            controller.expandedFileHeadings.contains(displayNode.path)) {
          final session = controller.sessions[displayNode.path];
          if (session != null) {
            for (final heading in session.headings) {
              output.add(
                _TreeRow(
                  node: displayNode,
                  displayName: heading.text,
                  depth: depth + 1,
                  expanded: false,
                  type: _TreeRowType.heading,
                  heading: heading,
                ),
              );
            }
          }
        }
      } else {
        output.add(
          _TreeRow(
            node: displayNode,
            displayName: segments.join('.'),
            depth: depth,
            expanded: expanded,
            type: _TreeRowType.directory,
          ),
        );
        if (displayNode.isDirectory && expanded) {
          _flatten(
            controller,
            controller.childrenFor(displayNode.path),
            depth + 1,
            output,
          );
        }
      }
    }
  }

  List<_TreeRow> _filterRows(List<_TreeRow> rows, String lowerFilter) {
    final result = <_TreeRow>[];
    bool keepSubsequent = false;
    for (final row in rows) {
      if (row.isHeading) {
        if (keepSubsequent) result.add(row);
      } else {
        keepSubsequent = row.node.name.toLowerCase().contains(lowerFilter);
        if (keepSubsequent) result.add(row);
      }
    }
    return result;
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.row,
    required this.selectedPath,
    required this.hoverMode,
    required this.hoverDistance,
    required this.onHoverChanged,
    required this.onTap,
    this.onArrowTap,
    this.onSecondaryTap,
  });

  final _TreeRow row;
  final String? selectedPath;
  final FileTreeHoverMode hoverMode;
  final int? hoverDistance;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final VoidCallback? onArrowTap;
  final void Function(Offset globalPosition)? onSecondaryTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  Timer? _tooltipHideTimer;

  @override
  void dispose() {
    _tooltipHideTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    widget.onHoverChanged(true);
    if (!widget.row.isFile) return;
    _tooltipHideTimer?.cancel();
    _tooltipHideTimer = Timer(const Duration(seconds: 1), () {
      Tooltip.dismissAllToolTips();
    });
  }

  void _onHoverExit() {
    widget.onHoverChanged(false);
    _tooltipHideTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final showArrow = row.isDirectory || (row.isFile && _canExpandHeadings);
    final selected = widget.selectedPath == row.node.path && !row.isHeading;
    final hovered = widget.hoverDistance == 0;
    final scale = widget.hoverMode == FileTreeHoverMode.highlight
        ? 1.0
        : switch (widget.hoverDistance) {
            0 => 1.25,
            1 => 1.13,
            2 => 1.06,
            _ => 1.0,
          };
    final background = widget.hoverMode == FileTreeHoverMode.scale
        ? Colors.transparent
        : selected
        ? AppColors.signal.withValues(alpha: 0.09)
        : hovered
        ? AppColors.surfaceHover.withValues(alpha: 0.55)
        : Colors.transparent;

    final body = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 175),
        curve: AppMotion.emphasized,
        scale: scale,
        alignment: Alignment.centerLeft,
        child: Container(
          color: background,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: row.isDirectory ? widget.onTap : null,
            onSecondaryTapDown: row.isHeading
                ? null
                : (details) =>
                      widget.onSecondaryTap?.call(details.globalPosition),
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                Row(
                  children: [
                    SizedBox(width: 10 + row.depth * 15),
                    if (showArrow)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: row.isFile ? widget.onArrowTap : widget.onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: AnimatedRotation(
                            duration: AppMotion.quick,
                            curve: AppMotion.emphasized,
                            turns: row.expanded ? 0.25 : 0,
                            child: Icon(
                              Icons.keyboard_arrow_right_rounded,
                              size: 14,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                    if (!row.isHeading) ...[
                      const SizedBox(width: 3),
                      _FileTypeIcon(node: row.node, expanded: row.expanded),
                      const SizedBox(width: 7),
                    ] else ...[
                      SizedBox(
                        width: 26,
                        child: Text(
                          'H${row.heading!.level}',
                          style: TextStyle(
                            color: _headingColor(row.heading!.level),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'MapleMonoCN',
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: row.isDirectory ? null : widget.onTap,
                      child: Row(
                        children: [
                          Expanded(
                            child: _FileName(
                              name: row.displayName,
                              emphasized: hovered,
                              selected: selected,
                              fontSize: row.isHeading ? 10.8 : 11.5,
                            ),
                          ),
                          if (row.dirty) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 3),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (selected)
                  Positioned(
                    left: 0,
                    top: 5,
                    bottom: 5,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: AppColors.signal.withValues(alpha: 0.84),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!row.isFile) return body;
    final withTooltip = Tooltip(
      message: truncatePathForDisplay(row.node.path),
      waitDuration: const Duration(milliseconds: 100),
      child: body,
    );
    return Draggable<PaneDragPayload>(
      data: PaneDragPayload(filePath: row.node.path),
      feedback: PaneDragFeedback(filePath: row.node.path),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: Opacity(opacity: 0.4, child: withTooltip),
      child: withTooltip,
    );
  }

  bool get _canExpandHeadings =>
      p.extension(widget.row.node.path).toLowerCase() == '.md' ||
      p.extension(widget.row.node.path).toLowerCase() == '.markdown';

  static Color _headingColor(int level) {
    return switch (level) {
      1 => AppColors.signal,
      2 => AppColors.signalDim,
      _ => AppColors.textDim,
    };
  }
}

class _FileName extends StatelessWidget {
  const _FileName({
    required this.name,
    required this.emphasized,
    required this.selected,
    required this.fontSize,
  });

  final String name;
  final bool emphasized;
  final bool selected;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: emphasized
            ? AppColors.text
            : selected
            ? AppColors.text
            : AppColors.textMuted,
        fontSize: fontSize,
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    if (!emphasized) return text;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: [AppColors.signal, AppColors.signalDim],
      ).createShader(bounds),
      child: text,
    );
  }
}

class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.node, required this.expanded});

  final FileNode node;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final visual = resolveFileVisual(
      FileIconContext(
        path: node.path,
        isDirectory: node.isDirectory,
        expanded: expanded,
      ),
    );
    if (visual.svgAssetKey != null) {
      return SizedBox(
        width: 18,
        height: 18,
        child: Center(
          child: SvgPicture.asset(
            visual.svgAssetKey!,
            width: 14,
            height: 14,
            colorFilter: visual.tintSvg && visual.color != null
                ? ColorFilter.mode(visual.color!, BlendMode.srcIn)
                : null,
          ),
        ),
      );
    }
    return Container(
      width: visual.label == null ? 20 : 24,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.color?.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(4),
      ),
      child: visual.label == null
          ? Icon(visual.icon, size: 13, color: visual.color)
          : Text(
              visual.label!,
              style: TextStyle(
                color: visual.color,
                fontSize: visual.label!.length > 3 ? 6.2 : 7.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
    );
  }
}

class _EmptyTree extends StatelessWidget {
  const _EmptyTree();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.layers_clear_outlined,
        color: AppColors.textDim,
        size: 25,
      ),
    );
  }
}

class _TreeRow {
  const _TreeRow({
    required this.node,
    required this.displayName,
    required this.depth,
    required this.expanded,
    this.type = _TreeRowType.file,
    this.heading,
    this.dirty = false,
  });

  final FileNode node;
  final String displayName;
  final int depth;
  final bool expanded;
  final _TreeRowType type;
  final MarkdownHeading? heading;
  final bool dirty;

  bool get isDirectory => type == _TreeRowType.directory;

  bool get isFile => type == _TreeRowType.file;

  bool get isHeading => type == _TreeRowType.heading;
}
