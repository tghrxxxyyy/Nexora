import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../app_theme.dart';
import '../models/terminal_layout.dart';
import '../services/terminal_session.dart';
import '../state/terminal_workspace_controller.dart';
import 'ui_primitives.dart';

/// Renders VS Code-style terminal controls and a recursive split pane layout.
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    required this.controller,
    required this.workingDirectory,
    required this.fontScale,
    super.key,
  });

  /// Controller that owns terminal processes and the split layout tree.
  final TerminalWorkspaceController controller;

  /// Directory used when toolbar actions create a new terminal.
  final String workingDirectory;
  final double fontScale;

  /// Builds terminal toolbar and all live panes from [controller].
  @override
  Widget build(BuildContext context) {
    final root = controller.layout;
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          _TerminalToolbar(
            controller: controller,
            workingDirectory: workingDirectory,
          ),
          Container(height: 1, color: AppColors.line),
          Expanded(
            child: root == null
                ? const SizedBox.shrink()
                : _buildLayoutNode(root),
          ),
        ],
      ),
    );
  }

  /// Recursively converts one layout model node into terminal pane widgets.
  ///
  /// Parameters:
  /// - [node]: leaf or split node to render.
  Widget _buildLayoutNode(TerminalLayoutNode node) {
    if (node is TerminalLeafNode) {
      final session = controller.sessionFor(node.terminalId);
      if (session == null) return const SizedBox.shrink();
      return _TerminalPane(
        key: ValueKey(session.id),
        session: session,
        active: controller.activeTerminalId == session.id,
        fontScale: fontScale,
        onActivate: () => controller.activate(session.id),
        onClose: () => unawaited(controller.closeTerminal(session.id)),
      );
    }

    final split = node as TerminalSplitNode;
    return _TerminalSplitView(
      node: split,
      firstChild: _buildLayoutNode(split.first),
      secondChild: _buildLayoutNode(split.second),
      onRatioChanged: (ratio) => controller.setSplitRatio(split.id, ratio),
    );
  }
}

/// Toolbar for new terminal, split direction, dock position, and panel hiding.
class _TerminalToolbar extends StatelessWidget {
  const _TerminalToolbar({
    required this.controller,
    required this.workingDirectory,
  });

  /// Controller receiving toolbar commands.
  final TerminalWorkspaceController controller;

  /// Directory assigned to terminals created by toolbar commands.
  final String workingDirectory;

  /// Builds a compact toolbar that remains usable in the narrow right dock.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.terminal_rounded, size: 15, color: AppColors.signal),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                controller.activeSession?.title ?? '终端',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (controller.terminalCount > 1)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${controller.terminalCount}',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 10,
                    letterSpacing: 0,
                  ),
                ),
              ),
            AppIconButton(
              icon: Icons.add_rounded,
              tooltip: '新建终端',
              size: 28,
              iconSize: 16,
              onPressed: () =>
                  controller.createTerminal(workingDirectory: workingDirectory),
            ),
            AppIconButton(
              icon: Icons.vertical_split_rounded,
              tooltip: '左右拆分终端',
              size: 28,
              iconSize: 16,
              onPressed: () => controller.splitActive(
                direction: TerminalSplitDirection.leftRight,
                workingDirectory: workingDirectory,
              ),
            ),
            AppIconButton(
              icon: Icons.horizontal_split_rounded,
              tooltip: '上下拆分终端',
              size: 28,
              iconSize: 16,
              onPressed: () => controller.splitActive(
                direction: TerminalSplitDirection.topBottom,
                workingDirectory: workingDirectory,
              ),
            ),
            const SizedBox(width: 3),
            AppIconButton(
              icon: Icons.vertical_align_bottom_rounded,
              tooltip: '终端停靠到底部',
              selected: controller.dock == TerminalDock.bottom,
              size: 28,
              iconSize: 16,
              onPressed: () => controller.setDock(TerminalDock.bottom),
            ),
            AppIconButton(
              icon: Icons.view_sidebar_outlined,
              tooltip: '终端停靠到右侧',
              selected: controller.dock == TerminalDock.right,
              size: 28,
              iconSize: 16,
              onPressed: () => controller.setDock(TerminalDock.right),
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: '隐藏终端',
              size: 28,
              iconSize: 16,
              onPressed: controller.hide,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays out two terminal children and exposes a draggable split divider.
class _TerminalSplitView extends StatelessWidget {
  const _TerminalSplitView({
    required this.node,
    required this.firstChild,
    required this.secondChild,
    required this.onRatioChanged,
  });

  /// Split direction and current first-child size ratio.
  final TerminalSplitNode node;

  /// Widget displayed on the left or top side.
  final Widget firstChild;

  /// Widget displayed on the right or bottom side.
  final Widget secondChild;

  /// Callback receiving a new first-child ratio during divider drag.
  final ValueChanged<double> onRatioChanged;

  /// Builds a row or column with stable child extents and resize handle.
  @override
  Widget build(BuildContext context) {
    final leftRight = node.direction == TerminalSplitDirection.leftRight;
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerExtent = 7.0;
        final totalExtent = leftRight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final availableExtent = math.max(0.0, totalExtent - dividerExtent);
        final firstExtent = availableExtent * node.ratio;
        return Flex(
          direction: leftRight ? Axis.horizontal : Axis.vertical,
          children: [
            SizedBox(
              width: leftRight ? firstExtent : null,
              height: leftRight ? null : firstExtent,
              child: firstChild,
            ),
            _TerminalSplitHandle(
              direction: node.direction,
              ratio: node.ratio,
              availableExtent: availableExtent,
              onRatioChanged: onRatioChanged,
            ),
            Expanded(child: secondChild),
          ],
        );
      },
    );
  }
}

/// Drag target between two terminal panes.
class _TerminalSplitHandle extends StatelessWidget {
  const _TerminalSplitHandle({
    required this.direction,
    required this.ratio,
    required this.availableExtent,
    required this.onRatioChanged,
  });

  /// Direction that determines drag axis and mouse cursor.
  final TerminalSplitDirection direction;

  /// Current first-child fraction before the next drag delta.
  final double ratio;

  /// Total resizable space shared by the two children.
  final double availableExtent;

  /// Callback receiving the ratio calculated from a drag delta.
  final ValueChanged<double> onRatioChanged;

  /// Builds the appropriate horizontal or vertical resize gesture target.
  @override
  Widget build(BuildContext context) {
    final leftRight = direction == TerminalSplitDirection.leftRight;
    return MouseRegion(
      cursor: leftRight
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: leftRight ? _handleHorizontalDrag : null,
        onVerticalDragUpdate: leftRight ? null : _handleVerticalDrag,
        child: SizedBox(
          width: leftRight ? 7 : double.infinity,
          height: leftRight ? double.infinity : 7,
          child: Center(
            child: Container(
              width: leftRight ? 1 : double.infinity,
              height: leftRight ? double.infinity : 1,
              color: AppColors.lineStrong,
            ),
          ),
        ),
      ),
    );
  }

  /// Applies a horizontal divider drag to the current split ratio.
  ///
  /// Parameters:
  /// - [details]: pointer delta reported by Flutter for this drag frame.
  void _handleHorizontalDrag(DragUpdateDetails details) {
    if (availableExtent <= 0) return;
    onRatioChanged(ratio + details.delta.dx / availableExtent);
  }

  /// Applies a vertical divider drag to the current split ratio.
  ///
  /// Parameters:
  /// - [details]: pointer delta reported by Flutter for this drag frame.
  void _handleVerticalDrag(DragUpdateDetails details) {
    if (availableExtent <= 0) return;
    onRatioChanged(ratio + details.delta.dy / availableExtent);
  }
}

/// Stateful terminal leaf that owns focus and text-selection UI state.
class _TerminalPane extends StatefulWidget {
  const _TerminalPane({
    required this.session,
    required this.active,
    required this.fontScale,
    required this.onActivate,
    required this.onClose,
    super.key,
  });

  /// Independent PTY and xterm emulator rendered by this pane.
  final TerminalSession session;

  /// Whether toolbar commands currently target this pane.
  final bool active;

  /// User-selected scale applied to terminal glyph metrics.
  final double fontScale;

  /// Callback that makes this pane active.
  final VoidCallback onActivate;

  /// Callback that closes this pane and terminates its PTY.
  final VoidCallback onClose;

  /// Creates focus and selection state for this terminal pane.
  @override
  State<_TerminalPane> createState() => _TerminalPaneState();
}

/// Focus, clipboard, and lifecycle state for one terminal pane.
class _TerminalPaneState extends State<_TerminalPane> {
  /// Selection controller used by copy, paste, and secondary click handling.
  final TerminalController _terminalController = TerminalController();

  /// Key used to convert global pointer positions into terminal cell offsets.
  final GlobalKey<TerminalViewState> _terminalViewKey = GlobalKey();

  /// Unconsumed high-resolution wheel distance, measured in logical pixels.
  double _wheelPixelRemainder = 0;

  /// Focus node used to route direct hardware keyboard input into xterm.
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'nexora-terminal-${widget.session.id}',
  );

  /// Starts the PTY after layout and focuses the initially active pane.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.session.start());
      if (widget.active) _focusNode.requestFocus();
    });
  }

  /// Restores keyboard focus when this pane becomes active.
  ///
  /// Parameters:
  /// - [oldWidget]: previous pane configuration used to detect activation.
  @override
  void didUpdateWidget(covariant _TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontScale != widget.fontScale) {
      _wheelPixelRemainder = 0;
    }
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  /// Releases focus and selection resources owned by this pane.
  @override
  void dispose() {
    _focusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  /// Builds pane chrome and the direct-input terminal viewport.
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onActivate(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(
            color: widget.active
                ? AppColors.signal.withValues(alpha: 0.34)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: _handleTerminalPointerSignal,
                child: TerminalView(
                  widget.session.terminal,
                  key: _terminalViewKey,
                  controller: _terminalController,
                  focusNode: _focusNode,
                  autofocus: widget.active,
                  theme: _buildTerminalTheme(),
                  textStyle: TerminalStyle(
                    fontSize: 12.5 * widget.fontScale,
                    height: 1.28,
                    fontFamily: 'MapleMonoCN',
                    fontFamilyFallback: [
                      'MesloLGS NF',
                      'JetBrainsMono Nerd Font',
                      'Menlo',
                      'Monaco',
                      'monospace',
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                  backgroundOpacity: 1,
                  keyboardAppearance: Theme.of(context).brightness,
                  cursorType: TerminalCursorType.block,
                  // The pane owns alternate-buffer wheel routing and fallback.
                  simulateScroll: false,
                  onTapUp: (_, _) {
                    widget.onActivate();
                    _focusNode.requestFocus();
                  },
                  onSecondaryTapDown: (_, _) {
                    unawaited(_handleSecondaryTap());
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Routes alternate-buffer wheel input using terminal-local cell coordinates.
  ///
  /// Parameters:
  /// - [event]: pointer signal emitted over this terminal pane.
  void _handleTerminalPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final terminal = widget.session.terminal;
    if (!terminal.isUsingAltBuffer) {
      _wheelPixelRemainder = 0;
      return;
    }
    if (event.scrollDelta.dy == 0) return;

    final terminalView = _terminalViewKey.currentState;
    if (terminalView == null) return;
    final renderTerminal = terminalView.renderTerminal;
    final lineHeight = renderTerminal.lineHeight;
    if (lineHeight <= 0) return;

    // Preserve sub-line trackpad deltas until they form a terminal row.
    _wheelPixelRemainder += event.scrollDelta.dy;
    final accumulatedLines = (_wheelPixelRemainder / lineHeight).truncate();
    if (accumulatedLines == 0) return;
    _wheelPixelRemainder -= accumulatedLines * lineHeight;

    final maxLinesPerEvent = math.max(1, terminal.viewHeight);
    final lines = accumulatedLines
        .clamp(-maxLinesPerEvent, maxLinesPerEvent)
        .toInt();
    // Convert from window coordinates after docking and split layout are applied.
    final localPosition = renderTerminal.globalToLocal(event.position);
    final cellPosition = renderTerminal.getCellOffset(localPosition);
    widget.session.sendAlternateBufferScroll(
      lines: lines,
      position: cellPosition,
    );
  }

  /// Builds the session title, process status, and close command.
  Widget _buildHeader() {
    return SizedBox(
      height: 29,
      child: Padding(
        padding: const EdgeInsets.only(left: 9, right: 3),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: widget.session,
              builder: (context, child) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _statusColor(widget.session.status),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.active ? AppColors.text : AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭此终端',
              size: 24,
              iconSize: 14,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  /// Copies the current selection or pastes clipboard text on secondary click.
  Future<void> _handleSecondaryTap() async {
    final selection = _terminalController.selection;
    if (selection != null) {
      final text = widget.session.terminal.buffer.getText(selection);
      await Clipboard.setData(ClipboardData(text: text));
      _terminalController.clearSelection();
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      widget.session.terminal.paste(text);
    }
  }

  /// Maps a PTY lifecycle state to the small pane status indicator.
  ///
  /// Parameters:
  /// - [status]: current lifecycle state of the terminal session.
  Color _statusColor(TerminalSessionStatus status) {
    return switch (status) {
      TerminalSessionStatus.running => AppColors.signal,
      TerminalSessionStatus.starting => AppColors.amber,
      TerminalSessionStatus.failed => AppColors.coral,
      TerminalSessionStatus.idle ||
      TerminalSessionStatus.exited => AppColors.textDim,
    };
  }

  /// Creates an ANSI palette that follows the active Nexora surface colors.
  TerminalTheme _buildTerminalTheme() {
    return TerminalTheme(
      cursor: AppColors.signal,
      selection: AppColors.selection,
      foreground: AppColors.text,
      background: AppColors.background,
      black: const Color(0xFF172126),
      red: AppColors.coral,
      green: const Color(0xFF3D9D7B),
      yellow: AppColors.amber,
      blue: const Color(0xFF3A7BA8),
      magenta: const Color(0xFF9A6DA8),
      cyan: const Color(0xFF168C8C),
      white: const Color(0xFFD6DEE2),
      brightBlack: const Color(0xFF788A91),
      brightRed: const Color(0xFFE5957C),
      brightGreen: const Color(0xFF67BE9D),
      brightYellow: const Color(0xFFD8B779),
      brightBlue: const Color(0xFF68A4D0),
      brightMagenta: const Color(0xFFB88AB8),
      brightCyan: const Color(0xFF5AA8A8),
      brightWhite: const Color(0xFFF4F7F8),
      searchHitBackground: AppColors.amber.withValues(alpha: 0.52),
      searchHitBackgroundCurrent: AppColors.signal,
      searchHitForeground: AppColors.background,
    );
  }
}
