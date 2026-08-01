import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/terminal_layout.dart';
import '../services/terminal_session.dart';

/// Manages terminal visibility, docking, independent PTYs, and split layout.
class TerminalWorkspaceController extends ChangeNotifier {
  /// Sessions keyed by the identifiers referenced by terminal layout leaves.
  final Map<String, TerminalSession> _sessions = {};

  /// Recursive root of the currently visible terminal pane arrangement.
  TerminalLayoutNode? _layout;

  /// Identifier of the pane that receives split and close commands.
  String? _activeTerminalId;

  /// Current edge at which the terminal workspace is docked.
  TerminalDock _dock = TerminalDock.bottom;

  /// Whether the terminal workspace is currently shown.
  bool _visible = false;

  /// Requested terminal height while docked at the bottom.
  double _bottomExtent = 260;

  /// Requested terminal width while docked on the right.
  double _rightExtent = 420;

  /// Sequence number used in terminal pane titles.
  int _nextDisplayIndex = 1;

  /// Sequence number used to identify split layout nodes.
  int _nextSplitId = 1;

  /// Current recursive pane layout, or null when no sessions exist.
  TerminalLayoutNode? get layout => _layout;

  /// Identifier of the currently active terminal pane.
  String? get activeTerminalId => _activeTerminalId;

  /// Current terminal dock edge.
  TerminalDock get dock => _dock;

  /// Whether the terminal workspace is visible.
  bool get visible => _visible;

  /// Requested height used by the bottom dock host.
  double get bottomExtent => _bottomExtent;

  /// Requested width used by the right dock host.
  double get rightExtent => _rightExtent;

  /// Number of independent PTY sessions in the current split layout.
  int get terminalCount => _sessions.length;

  /// Sessions ordered by their visual position in the split layout.
  List<TerminalSession> get sessions {
    final root = _layout;
    if (root == null) return const [];
    return root.terminalIds
        .map((id) => _sessions[id])
        .whereType<TerminalSession>()
        .toList(growable: false);
  }

  /// Currently active terminal session, or null when no pane exists.
  TerminalSession? get activeSession {
    final activeId = _activeTerminalId;
    return activeId == null ? null : _sessions[activeId];
  }

  /// Returns the terminal session referenced by a layout leaf.
  ///
  /// Parameters:
  /// - [terminalId]: identifier stored on a [TerminalLeafNode].
  TerminalSession? sessionFor(String terminalId) => _sessions[terminalId];

  /// Shows or hides the terminal while preserving running sessions.
  ///
  /// Parameters:
  /// - [workingDirectory]: directory used if the first session must be created.
  void toggle({required String workingDirectory}) {
    if (_visible) {
      hide();
      return;
    }
    if (_layout == null) {
      _createInitialTerminal(workingDirectory);
    }
    _visible = true;
    notifyListeners();
  }

  /// Hides the terminal workspace without terminating any PTY.
  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  /// Creates another terminal using the dock's natural split direction.
  ///
  /// Parameters:
  /// - [workingDirectory]: initial directory for the new login shell.
  void createTerminal({required String workingDirectory}) {
    if (_layout == null) {
      _createInitialTerminal(workingDirectory);
    } else {
      final direction = _dock == TerminalDock.bottom
          ? TerminalSplitDirection.leftRight
          : TerminalSplitDirection.topBottom;
      _splitActiveTerminal(direction, workingDirectory);
    }
    _visible = true;
    notifyListeners();
  }

  /// Splits the active pane and starts a new independent terminal beside it.
  ///
  /// Parameters:
  /// - [direction]: left/right or top/bottom arrangement for the new split.
  /// - [workingDirectory]: initial directory for the new login shell.
  void splitActive({
    required TerminalSplitDirection direction,
    required String workingDirectory,
  }) {
    if (_layout == null) {
      _createInitialTerminal(workingDirectory);
    } else {
      _splitActiveTerminal(direction, workingDirectory);
    }
    _visible = true;
    notifyListeners();
  }

  /// Marks one terminal pane as the target for subsequent toolbar commands.
  ///
  /// Parameters:
  /// - [terminalId]: identifier of the pane receiving focus.
  void activate(String terminalId) {
    if (!_sessions.containsKey(terminalId) || _activeTerminalId == terminalId) {
      return;
    }
    _activeTerminalId = terminalId;
    notifyListeners();
  }

  /// Closes one pane, terminates its PTY, and collapses empty split branches.
  ///
  /// Parameters:
  /// - [terminalId]: identifier of the terminal session to close.
  Future<void> closeTerminal(String terminalId) async {
    final session = _sessions.remove(terminalId);
    if (session == null) return;

    final root = _layout;
    _layout = root == null ? null : _removeTerminal(root, terminalId);
    if (_activeTerminalId == terminalId) {
      final remainingIds = _layout?.terminalIds.toList(growable: false);
      _activeTerminalId = remainingIds == null || remainingIds.isEmpty
          ? null
          : remainingIds.last;
    }
    if (_layout == null) {
      _visible = false;
    }
    notifyListeners();

    // Stop the child only after removing its pane from the visible layout.
    await session.kill();
    session.dispose();
  }

  /// Moves the live terminal workspace to another application edge.
  ///
  /// Parameters:
  /// - [dock]: target bottom or right dock edge.
  void setDock(TerminalDock dock) {
    if (_dock == dock) return;
    _dock = dock;
    notifyListeners();
  }

  /// Updates the requested size of the currently selected dock edge.
  ///
  /// Parameters:
  /// - [extent]: requested height for bottom dock or width for right dock.
  void setDockExtent(double extent) {
    final safeExtent = extent.clamp(100.0, 2400.0);
    if (_dock == TerminalDock.bottom) {
      if (_bottomExtent == safeExtent) return;
      _bottomExtent = safeExtent;
    } else {
      if (_rightExtent == safeExtent) return;
      _rightExtent = safeExtent;
    }
    notifyListeners();
  }

  /// Updates the first-child ratio for one recursive split node.
  ///
  /// Parameters:
  /// - [splitId]: stable identifier of the split being dragged.
  /// - [ratio]: requested first-child fraction from zero to one.
  void setSplitRatio(String splitId, double ratio) {
    final root = _layout;
    if (root == null) return;
    final replacement = _replaceSplitRatio(
      root,
      splitId,
      ratio.clamp(0.15, 0.85),
    );
    if (identical(root, replacement)) return;
    _layout = replacement;
    notifyListeners();
  }

  /// Restores non-process terminal preferences from the app session snapshot.
  ///
  /// Parameters:
  /// - [dock]: last selected dock edge.
  /// - [bottomExtent]: last requested bottom dock height.
  /// - [rightExtent]: last requested right dock width.
  void restorePreferences({
    required TerminalDock dock,
    required double bottomExtent,
    required double rightExtent,
  }) {
    _dock = dock;
    _bottomExtent = bottomExtent.clamp(100.0, 2400.0);
    _rightExtent = rightExtent.clamp(100.0, 2400.0);
    notifyListeners();
  }

  /// Terminates every PTY owned by this workspace during app shutdown.
  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _layout = null;
    super.dispose();
  }

  /// Creates the first leaf when no terminal layout currently exists.
  ///
  /// Parameters:
  /// - [workingDirectory]: initial directory for the new shell.
  void _createInitialTerminal(String workingDirectory) {
    final session = _createSession(workingDirectory);
    _layout = TerminalLeafNode(
      id: 'leaf-${session.id}',
      terminalId: session.id,
    );
    _activeTerminalId = session.id;
  }

  /// Replaces the active leaf with a split containing a new session.
  ///
  /// Parameters:
  /// - [direction]: visual direction of the new branch.
  /// - [workingDirectory]: initial directory for the new shell.
  void _splitActiveTerminal(
    TerminalSplitDirection direction,
    String workingDirectory,
  ) {
    final root = _layout;
    if (root == null) return;
    final targetId = _activeTerminalId ?? root.terminalIds.first;
    final session = _createSession(workingDirectory);
    final newLeaf = TerminalLeafNode(
      id: 'leaf-${session.id}',
      terminalId: session.id,
    );
    _layout = _replaceTerminalLeaf(
      root,
      targetId,
      (current) => TerminalSplitNode(
        id: 'split-${_nextSplitId++}',
        direction: direction,
        first: current,
        second: newLeaf,
      ),
    );
    _activeTerminalId = session.id;
  }

  /// Allocates a terminal session without starting it before its view mounts.
  ///
  /// Parameters:
  /// - [workingDirectory]: initial directory for the new shell.
  TerminalSession _createSession(String workingDirectory) {
    final session = TerminalSession(
      workingDirectory: workingDirectory,
      displayIndex: _nextDisplayIndex++,
    );
    session.addListener(() => _onSessionChanged(session));
    _sessions[session.id] = session;
    return session;
  }

  /// Auto-closes the pane when the underlying shell exits (e.g. `exit` typed),
  /// matching standard terminal behavior.
  void _onSessionChanged(TerminalSession session) {
    if (session.status == TerminalSessionStatus.exited) {
      unawaited(closeTerminal(session.id));
    }
  }

  /// Replaces a matching layout leaf while preserving unaffected branches.
  ///
  /// Parameters:
  /// - [node]: subtree currently being visited.
  /// - [terminalId]: identifier of the leaf to replace.
  /// - [replacement]: function that builds the replacement subtree.
  TerminalLayoutNode _replaceTerminalLeaf(
    TerminalLayoutNode node,
    String terminalId,
    TerminalLayoutNode Function(TerminalLeafNode current) replacement,
  ) {
    if (node is TerminalLeafNode) {
      return node.terminalId == terminalId ? replacement(node) : node;
    }
    final split = node as TerminalSplitNode;
    final first = _replaceTerminalLeaf(split.first, terminalId, replacement);
    final second = _replaceTerminalLeaf(split.second, terminalId, replacement);
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return split.copyWith(first: first, second: second);
  }

  /// Removes a terminal leaf and collapses branches left with one child.
  ///
  /// Parameters:
  /// - [node]: subtree currently being visited.
  /// - [terminalId]: identifier of the leaf to remove.
  TerminalLayoutNode? _removeTerminal(
    TerminalLayoutNode node,
    String terminalId,
  ) {
    if (node is TerminalLeafNode) {
      return node.terminalId == terminalId ? null : node;
    }
    final split = node as TerminalSplitNode;
    final first = _removeTerminal(split.first, terminalId);
    final second = _removeTerminal(split.second, terminalId);
    if (first == null) return second;
    if (second == null) return first;
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return split.copyWith(first: first, second: second);
  }

  /// Replaces one split ratio while preserving all other layout nodes.
  ///
  /// Parameters:
  /// - [node]: subtree currently being visited.
  /// - [splitId]: identifier of the split being resized.
  /// - [ratio]: clamped first-child size fraction.
  TerminalLayoutNode _replaceSplitRatio(
    TerminalLayoutNode node,
    String splitId,
    double ratio,
  ) {
    if (node is TerminalLeafNode) return node;
    final split = node as TerminalSplitNode;
    if (split.id == splitId) return split.copyWith(ratio: ratio);
    final first = _replaceSplitRatio(split.first, splitId, ratio);
    final second = _replaceSplitRatio(split.second, splitId, ratio);
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return split.copyWith(first: first, second: second);
  }
}
