import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/file_node.dart';
import '../models/markdown_heading.dart';
import '../state/app_controller.dart';
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
  String _filter = '';
  int? _hoveredRowIndex;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
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
          const SignalDivider(),
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: visibleRows.length,
                    itemExtent: 28,
                    itemBuilder: (context, index) {
                      final hoveredIndex = _hoveredRowIndex;
                      return _FileRow(
                        row: visibleRows[index],
                        selectedPath: workspace.selectedFilePath,
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

  static bool _isMarkdown(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  static String _normalize(String path) => p.normalize(p.absolute(path));

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
    required this.hoverDistance,
    required this.onHoverChanged,
    required this.onTap,
    this.onArrowTap,
  });

  final _TreeRow row;
  final String? selectedPath;
  final int? hoverDistance;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final VoidCallback? onArrowTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final showArrow = row.isDirectory || (row.isFile && _canExpandHeadings);
    final selected = widget.selectedPath == row.node.path && !row.isHeading;
    final scale = switch (widget.hoverDistance) {
      0 => 1.16,
      1 => 1.08,
      2 => 1.035,
      _ => 1.0,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 175),
        curve: AppMotion.emphasized,
        scale: scale,
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: row.isDirectory ? widget.onTap : null,
          child: Stack(
            children: [
              Row(
                children: [
                  SizedBox(width: 10 + row.depth * 13),
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
                            emphasized: widget.hoverDistance == 0,
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
            ? Colors.white
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
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF1A3145), Color(0xFF287AB8)],
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
    final visual = _visualFor(node, expanded);
    return Container(
      width: visual.label == null ? 20 : 24,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(4),
      ),
      child: visual.label == null
          ? Icon(visual.icon!, size: 13, color: visual.color)
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

  _FileVisual _visualFor(FileNode node, bool expanded) {
    if (node.isDirectory) {
      return _FileVisual(
        expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        AppColors.amber,
      );
    }
    return switch (p.extension(node.path).toLowerCase()) {
      '.md' || '.markdown' => _FileVisual.badge('MD', AppColors.signal),
      '.doc' ||
      '.docx' ||
      '.rtf' => _FileVisual(Icons.description_rounded, const Color(0xFF5AA8FF)),
      '.xls' ||
      '.xlsx' ||
      '.csv' => _FileVisual(Icons.table_chart_rounded, const Color(0xFF5BA7E7)),
      '.ppt' ||
      '.pptx' ||
      '.key' => _FileVisual(Icons.slideshow_rounded, const Color(0xFFFF9D5C)),
      '.pdf' => _FileVisual(Icons.picture_as_pdf_rounded, AppColors.coral),
      '.html' ||
      '.htm' ||
      '.xml' => _FileVisual(Icons.html_rounded, AppColors.coral),
      '.css' ||
      '.scss' ||
      '.less' => _FileVisual(Icons.style_rounded, const Color(0xFF8CB8FF)),
      '.java' ||
      '.kt' ||
      '.kts' => _FileVisual(Icons.coffee_rounded, const Color(0xFFFFA86A)),
      '.py' || '.pyi' => _FileVisual.badge('PY', const Color(0xFF7CB7FF)),
      '.js' || '.jsx' => _FileVisual.badge('JS', const Color(0xFFF3CE4B)),
      '.ts' || '.tsx' => _FileVisual.badge('TS', const Color(0xFF4C9CFF)),
      '.dart' => _FileVisual.badge('DART', const Color(0xFF55C4E7)),
      '.sql' => _FileVisual.badge('SQL', const Color(0xFFFFA86A)),
      '.json' ||
      '.yaml' ||
      '.yml' ||
      '.toml' ||
      '.ini' ||
      '.properties' => _FileVisual(Icons.tune_rounded, AppColors.acid),
      '.sh' ||
      '.zsh' ||
      '.bash' ||
      '.fish' => _FileVisual(Icons.terminal_rounded, const Color(0xFF8A9BB0)),
      '.go' ||
      '.rs' ||
      '.c' ||
      '.h' ||
      '.cpp' ||
      '.cc' ||
      '.cs' ||
      '.swift' => _FileVisual(Icons.code_rounded, const Color(0xFFA685FF)),
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.webp' ||
      '.svg' ||
      '.ico' => _FileVisual(Icons.image_outlined, const Color(0xFFE78AC9)),
      '.mp4' ||
      '.mov' ||
      '.avi' ||
      '.mkv' => _FileVisual(Icons.movie_outlined, const Color(0xFFCC8CFF)),
      '.mp3' ||
      '.wav' ||
      '.m4a' ||
      '.flac' => _FileVisual(Icons.audiotrack_rounded, const Color(0xFFDF82A9)),
      '.zip' ||
      '.rar' ||
      '.7z' ||
      '.tar' ||
      '.gz' => _FileVisual(Icons.inventory_2_outlined, AppColors.amber),
      _ => _FileVisual(Icons.insert_drive_file_outlined, AppColors.textDim),
    };
  }
}

class _FileVisual {
  const _FileVisual(this.icon, this.color) : label = null;

  const _FileVisual.badge(this.label, this.color) : icon = null;

  final IconData? icon;
  final String? label;
  final Color color;
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
