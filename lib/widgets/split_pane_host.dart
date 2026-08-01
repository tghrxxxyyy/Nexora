import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/split_layout.dart';
import '../state/app_controller.dart';
import 'pane_header.dart';
import 'pane_view.dart';
import 'split_divider.dart';
import 'split_drop_zone.dart';

/// Recursively renders a [SplitNode] tree. Each leaf becomes a [PaneView]
/// wrapped in a [SplitDropZone] (so files dropped on its edges trigger a
/// split); each branch lays out its primary/secondary subtrees along [axis]
/// with a draggable [SplitDivider] in between.
class SplitPaneHost extends StatelessWidget {
  const SplitPaneHost({
    required this.controller,
    required this.node,
    super.key,
  });

  final AppController controller;
  final SplitNode node;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      SplitLeaf(:final paneId, :final filePath) => _buildLeaf(paneId, filePath),
      SplitBranch(
        :final axis,
        :final ratio,
        :final primary,
        :final secondary,
      ) =>
        _buildBranch(axis, ratio, primary, secondary),
    };
  }

  Widget _buildLeaf(String paneId, String filePath) {
    final session = controller.paneSessionFor(paneId);
    final body = session == null
        ? _MissingPane(filePath: filePath)
        : PaneView(controller: controller, session: session);
    // Each pane in a split gets a per-pane tab strip (file tabs + a trailing
    // unsplit button). Single-pane mode (workspace.split == null) is rendered
    // by DocumentArea directly and doesn't go through SplitPaneHost, so no
    // header there.
    final withHeader = Column(
      children: [
        PaneHeader(
          controller: controller,
          paneId: paneId,
        ),
        Expanded(child: body),
      ],
    );
    return SplitDropZone(
      targetPaneId: paneId,
      onSplitEdge: (axis, primaryIsOld, payload) {
        // primaryIsOld=true (right/bottom drop): old pane stays primary, new
        // pane is the secondary. primaryIsOld=false (left/top drop): new pane
        // becomes primary, old pane demoted to secondary.
        controller.splitPane(
          targetPaneId: paneId,
          axis: axis,
          filePath: payload.filePath,
          newPaneIsSecondary: primaryIsOld,
        );
      },
      onReplaceCenter: (payload) =>
          controller.replacePaneDocument(paneId, payload.filePath),
      child: withHeader,
    );
  }

  Widget _buildBranch(
    SplitAxis axis,
    double ratio,
    SplitNode primary,
    SplitNode secondary,
  ) {
    final horizontal = axis == SplitAxis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final primaryFlex = (ratio * 100).clamp(10, 90).round();
        final secondaryFlex = 100 - primaryFlex;
        final children = <Widget>[
          Expanded(
            flex: primaryFlex,
            child: SplitPaneHost(controller: controller, node: primary),
          ),
          SplitDivider(
            axis: axis,
            onDelta: (delta) {
              // Convert raw pixel delta to a ratio delta against this branch's
              // extent. Negative deltas shrink primary (drag toward secondary).
              final extent = horizontal
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              if (extent <= 0) return;
              final firstLeafId = primary.leaves.first.paneId;
              controller.adjustSplitRatio(firstLeafId, delta / extent);
            },
            onDragEnd: () {
              final firstLeafId = primary.leaves.first.paneId;
              final parent = controller.activeSplit?.findParentBranch(firstLeafId);
              if (parent != null) {
                if (parent.ratio <= 0.15) {
                  controller.unsplitPane(secondary.leaves.first.paneId);
                } else if (parent.ratio >= 0.85) {
                  controller.unsplitPane(firstLeafId);
                }
              }
            },
          ),
          Expanded(
            flex: secondaryFlex,
            child: SplitPaneHost(controller: controller, node: secondary),
          ),
        ];
        return horizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}

/// Center pane placeholder shown when a paneId has no session yet (e.g. a
/// restored split tree pointed at a deleted file).
class _MissingPane extends StatelessWidget {
  const _MissingPane({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.background),
      child: Center(
        child: Text(
          '文件不可用\n$filePath',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 11),
        ),
      ),
    );
  }
}
