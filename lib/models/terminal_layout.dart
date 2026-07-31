/// Defines where the terminal workspace is docked in the application shell.
enum TerminalDock { bottom, right }

/// Defines how two terminal panes are arranged inside a split node.
enum TerminalSplitDirection { leftRight, topBottom }

/// Base node for the recursive terminal pane layout.
sealed class TerminalLayoutNode {
  const TerminalLayoutNode({required this.id});

  /// Stable identifier used to preserve and resize this layout node.
  final String id;

  /// Returns every terminal session identifier contained by this node.
  Iterable<String> get terminalIds;
}

/// Leaf node that displays one terminal session.
final class TerminalLeafNode extends TerminalLayoutNode {
  const TerminalLeafNode({required super.id, required this.terminalId});

  /// Identifier of the terminal session rendered by this leaf.
  final String terminalId;

  /// Returns the single terminal identifier owned by this leaf.
  @override
  Iterable<String> get terminalIds sync* {
    yield terminalId;
  }
}

/// Branch node that arranges two terminal layout children.
final class TerminalSplitNode extends TerminalLayoutNode {
  const TerminalSplitNode({
    required super.id,
    required this.direction,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  /// Visual direction used to arrange [first] and [second].
  final TerminalSplitDirection direction;

  /// Child displayed on the left or top side of the split.
  final TerminalLayoutNode first;

  /// Child displayed on the right or bottom side of the split.
  final TerminalLayoutNode second;

  /// Fraction of available space assigned to [first].
  final double ratio;

  /// Returns terminal identifiers from both child branches in visual order.
  @override
  Iterable<String> get terminalIds sync* {
    yield* first.terminalIds;
    yield* second.terminalIds;
  }

  /// Creates a node with selected fields replaced.
  ///
  /// Parameters:
  /// - [first]: replacement for the first child.
  /// - [second]: replacement for the second child.
  /// - [ratio]: replacement size fraction for the first child.
  TerminalSplitNode copyWith({
    TerminalLayoutNode? first,
    TerminalLayoutNode? second,
    double? ratio,
  }) {
    return TerminalSplitNode(
      id: id,
      direction: direction,
      first: first ?? this.first,
      second: second ?? this.second,
      ratio: ratio ?? this.ratio,
    );
  }
}
