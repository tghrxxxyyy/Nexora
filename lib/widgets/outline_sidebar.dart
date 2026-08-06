import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/markdown_heading.dart';
import '../state/app_controller.dart';
import '../state/editor_session.dart';
import 'ui_primitives.dart';

class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    required this.controller,
    required this.session,
    this.floating = false,
    super.key,
  });

  final AppController controller;
  final EditorSession session;
  final bool floating;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Map<String, bool> _expansionOverrides = {};
  int? _hoveredEntryIndex;

  @override
  Widget build(BuildContext context) {
    final headings = widget.session.headings;
    final entries = _visibleEntries(headings);
    final content = Column(
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
        SignalDivider(),
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
                          widget.controller.activeSession?.document.path ==
                              widget.session.document.path &&
                          widget.controller.activeHeadingAnchor ==
                              entry.heading.anchor,
                      hasChildren: entry.hasChildren,
                      expanded: _isExpanded(entry.heading),
                      hoverDistance: _hoveredEntryIndex == null
                          ? null
                          : (index - _hoveredEntryIndex!).abs(),
                      onHoverChanged: (hovered) {
                        setState(() {
                          if (hovered) {
                            _hoveredEntryIndex = index;
                          } else if (_hoveredEntryIndex == index) {
                            _hoveredEntryIndex = null;
                          }
                        });
                      },
                      onTap: () => widget.controller.jumpToHeadingInSession(
                        widget.session,
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
    );
    return widget.floating ? content : PanelSurface(child: content);
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

  /// Returns whether the heading at [index] directly owns a nested heading.
  ///
  /// Parameters:
  /// - [headings]: source-ordered Markdown heading list.
  /// - [index]: heading position whose immediate successor is inspected.
  bool _hasChildren(List<MarkdownHeading> headings, int index) {
    final nextIndex = index + 1;
    return nextIndex < headings.length &&
        headings[nextIndex].level > headings[index].level;
  }

  bool _isExpanded(MarkdownHeading heading) =>
      _expansionOverrides[heading.anchor] ?? heading.level == 1;

  void _toggle(MarkdownHeading heading) {
    setState(() {
      _expansionOverrides[heading.anchor] = !_isExpanded(heading);
    });
  }
}

/// Compact outline entry point used by each pane while the workspace is split.
class HoverOutlineMenu extends StatefulWidget {
  const HoverOutlineMenu({
    required this.controller,
    required this.session,
    required this.menuWidth,
    super.key,
  });

  final AppController controller;
  final EditorSession session;
  final double menuWidth;

  @override
  State<HoverOutlineMenu> createState() => _HoverOutlineMenuState();
}

class _HoverOutlineMenuState extends State<HoverOutlineMenu> {
  static const Duration _hideDelay = Duration(milliseconds: 80);

  final LayerLink _layerLink = LayerLink();
  final GlobalKey<_HoverOutlineOverlayState> _overlayKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;
  bool _hovered = false;
  bool _openAbove = false;
  double _overlayWidth = 270;
  double _overlayHeight = 400;

  @override
  void didUpdateWidget(covariant HoverOutlineMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: '文档目录',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _showOverlay(),
          onExit: (_) => _scheduleHide(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showOverlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: AppMotion.emphasized,
              width: 28,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.signal.withValues(
                  alpha: _hovered ? 0.11 : 0.045,
                ),
                borderRadius: BorderRadius.circular(AppColors.radius(4)),
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: AppMotion.emphasized,
                scale: _hovered ? 1.12 : 1,
                child: Icon(
                  Icons.format_list_bulleted_rounded,
                  size: 15,
                  color: _hovered ? AppColors.signal : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the pane outline and reverses an in-progress closing animation.
  void _showOverlay() {
    _keepOpen();
    final currentEntry = _overlayEntry;
    if (currentEntry != null) {
      return;
    }

    _updateOverlayGeometry();
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: _overlayWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: _openAbove ? Alignment.topRight : Alignment.bottomRight,
          followerAnchor: _openAbove
              ? Alignment.bottomRight
              : Alignment.topRight,
          offset: Offset(0, _openAbove ? -6 : 6),
          child: _HoverOutlineOverlay(
            key: _overlayKey,
            controller: widget.controller,
            session: widget.session,
            height: _overlayHeight,
            openAbove: _openAbove,
            onEnter: _keepOpen,
            onExit: _scheduleHide,
            onDismissed: _removeOverlay,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  /// Keeps the menu visible when the pointer reaches either connected region.
  void _keepOpen() {
    _hideTimer?.cancel();
    if (mounted && !_hovered) setState(() => _hovered = true);
    _overlayKey.currentState?.show();
  }

  /// Starts closing after the pointer has time to cross the target-menu gap.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && _hovered) setState(() => _hovered = false);
      final overlayState = _overlayKey.currentState;
      if (overlayState == null) {
        _removeOverlay();
      } else {
        overlayState.hide();
      }
    });
  }

  /// Removes the overlay only after its exit animation has completed.
  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry
      ..remove()
      ..dispose();
  }

  /// Fits the menu into the root overlay and chooses the roomier vertical side.
  void _updateOverlayGeometry() {
    final targetBox = context.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    if (targetBox is! RenderBox || overlayBox is! RenderBox) {
      _overlayWidth = widget.menuWidth;
      _overlayHeight = 400;
      _openAbove = false;
      return;
    }

    final targetOrigin = overlayBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    final targetBottom = targetOrigin.dy + targetBox.size.height;
    final availableBelow = overlayBox.size.height - targetBottom - 12;
    final availableAbove = targetOrigin.dy - 12;
    _openAbove = availableBelow < 220 && availableAbove > availableBelow;
    final verticalRoom = _openAbove ? availableAbove : availableBelow;
    _overlayHeight = verticalRoom.clamp(72.0, 400.0).toDouble();

    final targetRight = targetOrigin.dx + targetBox.size.width - 8;
    _overlayWidth = targetRight.clamp(1.0, widget.menuWidth).toDouble();
  }
}

class _HoverOutlineOverlay extends StatefulWidget {
  const _HoverOutlineOverlay({
    required this.controller,
    required this.session,
    required this.height,
    required this.openAbove,
    required this.onEnter,
    required this.onExit,
    required this.onDismissed,
    super.key,
  });

  final AppController controller;
  final EditorSession session;
  final double height;
  final bool openAbove;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onDismissed;

  @override
  State<_HoverOutlineOverlay> createState() => _HoverOutlineOverlayState();
}

class _HoverOutlineOverlayState extends State<_HoverOutlineOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..addStatusListener(_handleAnimationStatus);
    final curved = CurvedAnimation(
      parent: _animationController,
      curve: AppMotion.emphasized,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(
      begin: Offset(0, widget.openAbove ? 0.045 : -0.045),
      end: Offset.zero,
    ).animate(curved);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => widget.onExit(),
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: Material(
            type: MaterialType.transparency,
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, child) => Container(
                height: widget.height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.surfaceRaised.withValues(alpha: 0.94),
                      AppColors.backgroundRaised.withValues(alpha: 0.88),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppColors.radius(6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.13),
                      blurRadius: 24,
                      spreadRadius: -7,
                      offset: const Offset(0, 9),
                    ),
                  ],
                ),
                child: OutlinePanel(
                  controller: widget.controller,
                  session: widget.session,
                  floating: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reopens the menu when the pointer returns during its reverse animation.
  void show() {
    _animationController.forward();
  }

  /// Plays the fast exit animation before asking the owner to remove Overlay.
  void hide() {
    _animationController.reverse();
  }

  /// Notifies the owner once the closing animation reaches its dismissed state.
  ///
  /// Parameters:
  /// - [status]: current lifecycle state of the outline animation.
  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) widget.onDismissed();
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
    required this.hoverDistance,
    required this.onHoverChanged,
    required this.onTap,
    this.onToggle,
    super.key,
  });

  final MarkdownHeading heading;
  final bool selected;
  final bool hasChildren;
  final bool expanded;
  final int? hoverDistance;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  State<_HeadingRow> createState() => _HeadingRowState();
}

class _HeadingRowState extends State<_HeadingRow> {
  @override
  Widget build(BuildContext context) {
    final heading = widget.heading;
    final scale = switch (widget.hoverDistance) {
      0 => 1.23,
      1 => 1.12,
      2 => 1.055,
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
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                8 + (heading.level - 1) * 9,
                6,
                10,
                6,
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
                    child: _OutlineName(
                      name: heading.text,
                      emphasized: widget.hoverDistance == 0,
                      selected: widget.selected,
                      fontSize: heading.level == 1 ? 11.5 : 10.8,
                      fontWeight: heading.level <= 2
                          ? FontWeight.w600
                          : FontWeight.w400,
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
        ),
      ),
    );
  }
}

class _OutlineName extends StatelessWidget {
  const _OutlineName({
    required this.name,
    required this.emphasized,
    required this.selected,
    required this.fontSize,
    required this.fontWeight,
  });

  final String name;
  final bool emphasized;
  final bool selected;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: emphasized
            ? AppColors.text
            : selected
            ? AppColors.text
            : AppColors.textMuted,
        fontSize: fontSize,
        height: 1.35,
        fontWeight: emphasized ? FontWeight.w700 : fontWeight,
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

class _EmptyOutline extends StatelessWidget {
  const _EmptyOutline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.toc_rounded, color: AppColors.textDim, size: 25),
    );
  }
}
