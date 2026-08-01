import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/split_layout.dart';

/// Resize handle between two panes in a split branch. Mirrors the existing
/// `_TerminalDockResizeHandle` pattern: 8px hit area + 1px visual rule, axis
/// switches with [axis]. Forwards raw pointer delta to [onDelta] so the
/// controller can convert it to a ratio change for the owning branch.
class SplitDivider extends StatelessWidget {
  const SplitDivider({
    required this.axis,
    required this.onDelta,
    required this.onDragEnd,
    super.key,
  });

  final SplitAxis axis;
  final ValueChanged<double> onDelta;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == SplitAxis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? (details) => onDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => onDelta(details.delta.dy),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onVerticalDragEnd: (_) => onDragEnd(),
        child: ColoredBox(
          color: AppColors.background,
          child: SizedBox(
            width: horizontal ? 8 : double.infinity,
            height: horizontal ? double.infinity : 8,
            child: Center(
              child: Container(
                width: horizontal ? 1 : double.infinity,
                height: horizontal ? double.infinity : 1,
                color: AppColors.lineStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
