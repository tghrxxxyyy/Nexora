/// Tree-structured split layout for a workspace.
///
/// A workspace either shows a single document (`SplitLeaf`) or a nested
/// arrangement of split panes (`SplitBranch`). The tree supports arbitrary
/// nesting depth: a `SplitBranch` can contain further `SplitBranch` children
/// on either side.
library;

/// Direction of a split. `horizontal` lays children out left/right; `vertical`
/// stacks them top/bottom.
enum SplitAxis { horizontal, vertical }

/// Base type for nodes in a split tree.
sealed class SplitNode {
  const SplitNode();

  Map<String, dynamic> toJson();

  /// Collects every leaf in this subtree (depth-first, primary before
  /// secondary).
  List<SplitLeaf> get leaves;

  /// True if this subtree contains a leaf with [paneId].
  bool containsPane(String paneId);

  /// Returns a copy of this subtree with the descendant leaf identified by
  /// [paneId] replaced by [replacement]. Returns `null` if [paneId] isn't in
  /// this subtree.
  SplitNode? replacePane(String paneId, SplitNode replacement);

  /// Returns the subtree that results from removing the leaf with [paneId]
  /// and collapsing its parent branch — the pane's sibling subtree is
  /// promoted in place of the parent. Returns `null` only if the entire
  /// subtree was that single leaf (i.e. [paneId] was the only leaf here).
  SplitNode? collapseLeaf(String paneId);

  /// Finds the immediate parent branch containing a leaf with [paneId].
  /// Returns `null` when [paneId] is the top-level leaf or isn't present.
  SplitBranch? findParentBranch(String paneId);

  static SplitNode fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw FormatException('SplitNode JSON must be a map');
    }
    final type = json['t'];
    switch (type) {
      case 'leaf':
        final paths = json['paths'];
        if (paths is List && paths.isNotEmpty) {
          final active = (json['active'] as num?)?.toInt() ?? 0;
          return SplitLeaf(
            paneId: json['id'] as String,
            openPaths: paths.cast<String>(),
            activeIndex: active.isNegative ? 0 : active,
          );
        }
        // Backwards compat: pre-multi-tab format stored a single 'path'.
        return SplitLeaf(
          paneId: json['id'] as String,
          openPaths: [json['path'] as String],
        );
      case 'branch':
        final axisIndex = json['axis'] as int;
        return SplitBranch(
          axis: SplitAxis.values[axisIndex.clamp(0, SplitAxis.values.length - 1)],
          primary: SplitNode.fromJson(json['primary']),
          secondary: SplitNode.fromJson(json['secondary']),
          ratio: (json['ratio'] as num).toDouble(),
        );
      default:
        throw FormatException('Unknown SplitNode type: $type');
    }
  }
}

/// A single pane showing one document at a time, but possibly with multiple
/// documents open as tabs within the pane (VSCode editor-group style).
class SplitLeaf extends SplitNode {
  const SplitLeaf({
    required this.paneId,
    required this.openPaths,
    this.activeIndex = 0,
  });

  /// Stable unique identifier for this pane. Survives ratio drags and view
  /// mode changes so the rendered `EditorSession` can be reused.
  final String paneId;

  /// All documents open as tabs within this pane. The active one (shown in
  /// the editor body) is [openPaths] [[activeIndex]].
  final List<String> openPaths;

  /// Index into [openPaths] of the currently visible document.
  final int activeIndex;

  /// Convenience accessor for the path of the active document.
  String get filePath {
    if (openPaths.isEmpty) return '';
    final i = activeIndex.clamp(0, openPaths.length - 1);
    return openPaths[i];
  }

  @override
  Map<String, dynamic> toJson() => {
        't': 'leaf',
        'id': paneId,
        'paths': openPaths,
        'active': activeIndex,
      };

  @override
  List<SplitLeaf> get leaves => [this];

  @override
  bool containsPane(String paneId) => this.paneId == paneId;

  @override
  SplitNode? replacePane(String paneId, SplitNode replacement) =>
      this.paneId == paneId ? replacement : null;

  @override
  SplitNode? collapseLeaf(String paneId) =>
      this.paneId == paneId ? null : this;

  @override
  SplitBranch? findParentBranch(String paneId) => null;

  SplitLeaf copyWith({
    List<String>? openPaths,
    int? activeIndex,
  }) =>
      SplitLeaf(
        paneId: paneId,
        openPaths: openPaths ?? this.openPaths,
        activeIndex: activeIndex ?? this.activeIndex,
      );
}

/// An interior split node dividing space between [primary] and [secondary]
/// along [axis]. [ratio] is primary's share, clamped to a sensible range by
/// the controller.
class SplitBranch extends SplitNode {
  const SplitBranch({
    required this.axis,
    required this.primary,
    required this.secondary,
    required this.ratio,
  });

  final SplitAxis axis;
  final SplitNode primary;
  final SplitNode secondary;
  final double ratio;

  @override
  Map<String, dynamic> toJson() => {
        't': 'branch',
        'axis': axis.index,
        'primary': primary.toJson(),
        'secondary': secondary.toJson(),
        'ratio': ratio,
      };

  @override
  List<SplitLeaf> get leaves => [...primary.leaves, ...secondary.leaves];

  @override
  bool containsPane(String paneId) =>
      primary.containsPane(paneId) || secondary.containsPane(paneId);

  @override
  SplitNode? replacePane(String paneId, SplitNode replacement) {
    final newPrimary = primary.replacePane(paneId, replacement);
    if (newPrimary != null) {
      return SplitBranch(
        axis: axis,
        primary: newPrimary,
        secondary: secondary,
        ratio: ratio,
      );
    }
    final newSecondary = secondary.replacePane(paneId, replacement);
    if (newSecondary != null) {
      return SplitBranch(
        axis: axis,
        primary: primary,
        secondary: newSecondary,
        ratio: ratio,
      );
    }
    return null;
  }

  @override
  SplitNode? collapseLeaf(String paneId) {
    // If paneId is a direct leaf child, promote the sibling to replace us.
    if (primary is SplitLeaf && (primary as SplitLeaf).paneId == paneId) {
      return secondary;
    }
    if (secondary is SplitLeaf && (secondary as SplitLeaf).paneId == paneId) {
      return primary;
    }
    // Otherwise recurse into whichever side contains it.
    if (primary.containsPane(paneId)) {
      final collapsed = primary.collapseLeaf(paneId);
      if (collapsed == null) return secondary;
      return SplitBranch(
        axis: axis,
        primary: collapsed,
        secondary: secondary,
        ratio: ratio,
      );
    }
    if (secondary.containsPane(paneId)) {
      final collapsed = secondary.collapseLeaf(paneId);
      if (collapsed == null) return primary;
      return SplitBranch(
        axis: axis,
        primary: primary,
        secondary: collapsed,
        ratio: ratio,
      );
    }
    return this;
  }

  @override
  SplitBranch? findParentBranch(String paneId) {
    if (!containsPane(paneId)) return null;
    if (primary is SplitLeaf && (primary as SplitLeaf).paneId == paneId) return this;
    if (secondary is SplitLeaf && (secondary as SplitLeaf).paneId == paneId) return this;
    if (primary is SplitBranch) {
      final found = (primary as SplitBranch).findParentBranch(paneId);
      if (found != null) return found;
    }
    if (secondary is SplitBranch) {
      final found = (secondary as SplitBranch).findParentBranch(paneId);
      if (found != null) return found;
    }
    return null;
  }

  SplitBranch copyWith({
    SplitAxis? axis,
    SplitNode? primary,
    SplitNode? secondary,
    double? ratio,
  }) =>
      SplitBranch(
        axis: axis ?? this.axis,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        ratio: ratio ?? this.ratio,
      );
}
