import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/split_layout.dart';
import 'pane_drag_payload.dart';

/// Where in the pane a drop is currently hovering. Maps 1:1 to the four
/// directional split edges plus the centered "replace" zone.
enum _DropZone { none, left, right, top, bottom, center }

/// Wraps a pane and overlays VSCode-style half-region highlights while a
/// [PaneDragPayload] is being dragged over it. On drop, fires the matching
/// callback so the controller can either split the pane or replace its
/// document.
class SplitDropZone extends StatefulWidget {
  const SplitDropZone({
    required this.targetPaneId,
    required this.child,
    required this.onSplitEdge,
    required this.onReplaceCenter,
    super.key,
  });

  final String targetPaneId;
  final Widget child;

  /// Fires when a payload is dropped on a directional edge. The [axis] is
  /// already resolved (horizontal for left/right, vertical for top/bottom)
  /// and the secondary leaf's position is implied by the edge.
  final void Function(SplitAxis axis, bool primaryIsOld, PaneDragPayload payload)
      onSplitEdge;

  /// Fires when a payload is dropped on the center of the pane — replaces the
  /// pane's current document with the payload's file.
  final void Function(PaneDragPayload payload) onReplaceCenter;

  @override
  State<SplitDropZone> createState() => _SplitDropZoneState();
}

class _SplitDropZoneState extends State<SplitDropZone> {
  _DropZone _hovered = _DropZone.none;
  static const double _edgeBand = 0.32;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return DragTarget<PaneDragPayload>(
          onWillAcceptWithDetails: (details) {
            if (details.data.sourcePaneId == widget.targetPaneId) return false;
            return true;
          },
          onMove: (details) {
            final zone = _resolveZone(constraints, details.offset);
            if (zone != _hovered) {
              setState(() => _hovered = zone);
            }
          },
          onLeave: (_) {
            if (_hovered != _DropZone.none) {
              setState(() => _hovered = _DropZone.none);
            }
          },
          onAcceptWithDetails: (details) {
            final zone = _resolveZone(constraints, details.offset);
            final payload = details.data;
            setState(() => _hovered = _DropZone.none);
            switch (zone) {
              case _DropZone.left:
                widget.onSplitEdge(SplitAxis.horizontal, false, payload);
                break;
              case _DropZone.right:
                widget.onSplitEdge(SplitAxis.horizontal, true, payload);
                break;
              case _DropZone.top:
                widget.onSplitEdge(SplitAxis.vertical, false, payload);
                break;
              case _DropZone.bottom:
                widget.onSplitEdge(SplitAxis.vertical, true, payload);
                break;
              case _DropZone.center:
                widget.onReplaceCenter(payload);
                break;
              case _DropZone.none:
                break;
            }
          },
          builder: (context, candidate, rejected) {
            return Stack(
              children: [
                RepaintBoundary(child: widget.child),
                if (_hovered != _DropZone.none)
                  IgnorePointer(
                    child: _buildOverlay(_hovered),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOverlay(_DropZone zone) {
    final tint = AppColors.signal.withValues(alpha: 0.22);
    final border = AppColors.signal.withValues(alpha: 0.85);
    final decoration = BoxDecoration(
      color: tint,
      border: Border.fromBorderSide(
        BorderSide(color: border, width: 1.5),
      ),
      borderRadius: BorderRadius.circular(4),
    );

    switch (zone) {
      case _DropZone.left:
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(decoration: decoration),
          ),
        );
      case _DropZone.right:
        return Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(decoration: decoration),
          ),
        );
      case _DropZone.top:
        return Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.5,
            child: DecoratedBox(decoration: decoration),
          ),
        );
      case _DropZone.bottom:
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.5,
            child: DecoratedBox(decoration: decoration),
          ),
        );
      case _DropZone.center:
        return Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              border: Border.fromBorderSide(
                BorderSide(color: border, width: 1.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      case _DropZone.none:
        return const SizedBox.shrink();
    }
  }

  _DropZone _resolveZone(BoxConstraints constraints, Offset offset) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    if (w <= 0 || h <= 0) return _DropZone.center;
    final dx = offset.dx / w;
    final dy = offset.dy / h;
    if (dx < _edgeBand) return _DropZone.left;
    if (dx > 1 - _edgeBand) return _DropZone.right;
    if (dy < _edgeBand) return _DropZone.top;
    if (dy > 1 - _edgeBand) return _DropZone.bottom;
    return _DropZone.center;
  }
}
