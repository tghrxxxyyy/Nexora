import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/markdown_heading.dart';
import '../state/app_controller.dart';
import 'ui_primitives.dart';

class OutlinePanel extends StatefulWidget {
  const OutlinePanel({required this.controller, super.key});

  final AppController controller;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Map<String, bool> _expansionOverrides = {};

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.activeSession;
    final headings = session?.headings ?? const <MarkdownHeading>[];
    final entries = _visibleEntries(headings);
    return PanelSurface(
      child: Column(
        children: [
          PanelLabel(
            label: '文档索引',
            trailing: Text(
              headings.length.toString().padLeft(2, '0'),
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 9.5,
                fontFamily: 'MapleMonoCN',
              ),
            ),
          ),
          const SignalDivider(),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyOutline()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    physics: const ClampingScrollPhysics(),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _HeadingRow(
                        key: ValueKey(entry.heading.anchor),
                        heading: entry.heading,
                        selected:
                            widget.controller.activeHeadingAnchor ==
                            entry.heading.anchor,
                        hasChildren: entry.hasChildren,
                        expanded: _isExpanded(entry.heading),
                        onTap: () => widget.controller.jumpToHeading(
                          entry.heading.lineNumber,
                          entry.heading.anchor,
                        ),
                        onToggle: entry.hasChildren
                            ? () => _toggle(entry.heading)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_OutlineEntry> _visibleEntries(List<MarkdownHeading> headings) {
    final visible = <_OutlineEntry>[];
    final ancestors = <MarkdownHeading>[];
    for (var index = 0; index < headings.length; index++) {
      final heading = headings[index];
      while (ancestors.isNotEmpty && ancestors.last.level >= heading.level) {
        ancestors.removeLast();
      }
      if (ancestors.every(_isExpanded)) {
        visible.add(
          _OutlineEntry(
            heading: heading,
            hasChildren: _hasChildren(headings, index),
          ),
        );
      }
      ancestors.add(heading);
    }
    return visible;
  }

  bool _hasChildren(List<MarkdownHeading> headings, int index) {
    final level = headings[index].level;
    for (var cursor = index + 1; cursor < headings.length; cursor++) {
      final nextLevel = headings[cursor].level;
      if (nextLevel <= level) return false;
      return true;
    }
    return false;
  }

  bool _isExpanded(MarkdownHeading heading) =>
      _expansionOverrides[heading.anchor] ?? false;

  void _toggle(MarkdownHeading heading) {
    setState(() {
      _expansionOverrides[heading.anchor] = !_isExpanded(heading);
    });
  }
}

class _OutlineEntry {
  const _OutlineEntry({required this.heading, required this.hasChildren});

  final MarkdownHeading heading;
  final bool hasChildren;
}

class _HeadingRow extends StatefulWidget {
  const _HeadingRow({
    required this.heading,
    required this.selected,
    required this.hasChildren,
    required this.expanded,
    required this.onTap,
    this.onToggle,
    super.key,
  });

  final MarkdownHeading heading;
  final bool selected;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  State<_HeadingRow> createState() => _HeadingRowState();
}

class _HeadingRowState extends State<_HeadingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final heading = widget.heading;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.fromLTRB(8 + (heading.level - 1) * 9, 6, 10, 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.signal.withValues(alpha: 0.085)
                : _hovered
                ? AppColors.signal.withValues(alpha: 0.028)
                : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: widget.hasChildren
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onToggle,
                        child: AnimatedRotation(
                          duration: AppMotion.quick,
                          curve: AppMotion.emphasized,
                          turns: widget.expanded ? 0.25 : 0,
                          child: Icon(
                            Icons.keyboard_arrow_right_rounded,
                            size: 15,
                            color: widget.selected
                                ? AppColors.signal
                                : AppColors.textDim,
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(
                width: 22,
                child: Text(
                  'H${heading.level}',
                  style: TextStyle(
                    color: widget.selected || heading.level <= 2
                        ? AppColors.signal
                        : AppColors.textDim,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'MapleMonoCN',
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  heading.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.selected || _hovered
                        ? AppColors.text
                        : AppColors.textMuted,
                    fontSize: heading.level == 1 ? 11.5 : 10.8,
                    height: 1.35,
                    fontWeight: heading.level <= 2
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                heading.lineNumber.toString(),
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 8.5,
                  fontFamily: 'MapleMonoCN',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyOutline extends StatelessWidget {
  const _EmptyOutline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.toc_rounded, color: AppColors.textDim, size: 25),
    );
  }
}
