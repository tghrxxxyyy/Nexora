import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:xterm/xterm.dart';

import '../app_theme.dart';
import '../models/terminal_layout.dart';
import '../models/workspace_item.dart';
import '../state/app_controller.dart';
import '../state/editor_session.dart';
import 'document_area.dart';
import 'editor_find_panel.dart';
import 'file_sidebar.dart';
import 'git_panel.dart';
import 'global_search_panel.dart';
import 'preview_find_panel.dart';
import 'status_bar.dart';
import 'terminal_panel.dart';
import 'ui_primitives.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.controller,
    required this.onShowSettings,
    super.key,
  });

  final AppController controller;
  final VoidCallback onShowSettings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_terminalHasFocus()) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.closeCurrentFileFind();
      return true;
    }

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    // Ctrl-based editing shortcuts. re_editor only binds Cmd on macOS, so a
    // physical Ctrl+C/V/... does nothing there; on Linux/Windows consuming the
    // event here is equivalent to re_editor's own Ctrl bindings. Only fire when
    // focus is inside a CodeEditor — never in a find panel, where the input
    // TextField needs Ctrl+C/V for its own content.
    if (isCtrl && !isCmd) {
      final editor = _focusedEditor;
      if (editor != null) {
        if (!isShift && key == LogicalKeyboardKey.keyC) {
          editor.copy();
          return true;
        }
        if (!isShift && key == LogicalKeyboardKey.keyV) {
          editor.paste();
          return true;
        }
        if (!isShift && key == LogicalKeyboardKey.keyX) {
          editor.cut();
          return true;
        }
        if (!isShift && key == LogicalKeyboardKey.keyA) {
          editor.selectAll();
          return true;
        }
        if (!isShift && key == LogicalKeyboardKey.keyZ) {
          editor.undo();
          return true;
        }
        if (isShift && key == LogicalKeyboardKey.keyZ) {
          editor.redo();
          return true;
        }
        if (!isShift && key == LogicalKeyboardKey.keyY) {
          editor.redo();
          return true;
        }
      }
    }

    // Cmd+F on macOS, Ctrl+F elsewhere (and on macOS for users coming from
    // other platforms) — both open find-in-file. Shift still routes to global
    // search via the CallbackShortcuts binding below.
    if ((isCmd || isCtrl) && !isShift && key == LogicalKeyboardKey.keyF) {
      controller.openCurrentFileFind();
      return true;
    }
    return false;
  }

  /// The editing controller of the focused [CodeEditor], or null when focus is
  /// not inside one (including find panels, whose TextFields own the focus).
  CodeLineEditingController? get _focusedEditor {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return null;
    if (focusContext.findAncestorWidgetOfExactType<EditorFindPanel>() != null) {
      return null;
    }
    if (focusContext.findAncestorWidgetOfExactType<PreviewFindPanel>() !=
        null) {
      return null;
    }
    return focusContext.findAncestorWidgetOfExactType<CodeEditor>()?.controller;
  }

  /// Returns whether direct keyboard input currently belongs to a terminal.
  bool _terminalHasFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is TerminalView ||
        focusContext.findAncestorWidgetOfExactType<TerminalView>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            controller.saveActiveDocument,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            controller.undoActiveDocument,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            controller.redoActiveDocument,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            controller.openFiles,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
            controller.openDirectories,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            controller.showGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true):
            controller.showGlobalReplace,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            controller.toggleLeftSidebar,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            return Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.background),
                  Column(
                    children: [
                      _WorkspaceHeader(controller: controller),
                      SignalDivider(),
                      Expanded(child: _buildWorkspaceWithTerminal()),
                      StatusBar(controller: controller),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Builds the editor and live terminal using the selected dock edge.
  Widget _buildWorkspaceWithTerminal() {
    final terminalWorkspace = controller.terminalWorkspace;
    if (!terminalWorkspace.visible) {
      return _WorkspaceBody(
        controller: controller,
        onShowSettings: widget.onShowSettings,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final terminal = TerminalPanel(
          controller: terminalWorkspace,
          workingDirectory: controller.terminalWorkingDirectory,
          fontScale: controller.fontScale,
        );
        if (terminalWorkspace.dock == TerminalDock.right) {
          final extent = _effectiveDockExtent(
            requested: terminalWorkspace.rightExtent,
            available: constraints.maxWidth,
            preferredMinimum: 300,
            reservedWorkspace: 280,
          );
          return Row(
            children: [
              Expanded(
                child: _WorkspaceBody(
                  controller: controller,
                  onShowSettings: widget.onShowSettings,
                ),
              ),
              _TerminalDockResizeHandle(
                dock: TerminalDock.right,
                onDelta: (delta) =>
                    terminalWorkspace.setDockExtent(extent - delta),
              ),
              SizedBox(width: extent, child: terminal),
            ],
          );
        }

        final extent = _effectiveDockExtent(
          requested: terminalWorkspace.bottomExtent,
          available: constraints.maxHeight,
          preferredMinimum: 170,
          reservedWorkspace: 180,
        );
        return Column(
          children: [
            Expanded(
              child: _WorkspaceBody(
                controller: controller,
                onShowSettings: widget.onShowSettings,
              ),
            ),
            _TerminalDockResizeHandle(
              dock: TerminalDock.bottom,
              onDelta: (delta) =>
                  terminalWorkspace.setDockExtent(extent - delta),
            ),
            SizedBox(height: extent, child: terminal),
          ],
        );
      },
    );
  }

  /// Clamps one dock dimension while reserving usable space for the editor.
  ///
  /// Parameters:
  /// - [requested]: persisted or dragged terminal dimension.
  /// - [available]: total width or height of the editor host.
  /// - [preferredMinimum]: normal minimum terminal dimension.
  /// - [reservedWorkspace]: normal minimum dimension left for the editor.
  double _effectiveDockExtent({
    required double requested,
    required double available,
    required double preferredMinimum,
    required double reservedWorkspace,
  }) {
    const dividerExtent = 8.0;
    final reserved = math.min(reservedWorkspace, available * 0.45);
    final maximum = math.max(0.0, available - reserved - dividerExtent);
    final minimum = math.min(preferredMinimum, maximum);
    return requested.clamp(minimum, maximum);
  }
}

/// Drag handle between the document workspace and the terminal dock.
class _TerminalDockResizeHandle extends StatelessWidget {
  const _TerminalDockResizeHandle({required this.dock, required this.onDelta});

  /// Dock edge that determines the resize axis and mouse cursor.
  final TerminalDock dock;

  /// Callback receiving the raw pointer delta along the resize axis.
  final ValueChanged<double> onDelta;

  /// Builds a stable eight-pixel resize target around a one-pixel rule.
  @override
  Widget build(BuildContext context) {
    final rightDock = dock == TerminalDock.right;
    return MouseRegion(
      cursor: rightDock
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: rightDock
            ? (details) => onDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: rightDock
            ? null
            : (details) => onDelta(details.delta.dy),
        child: ColoredBox(
          color: AppColors.background,
          child: SizedBox(
            width: rightDock ? 8 : double.infinity,
            height: rightDock ? double.infinity : 8,
            child: Center(
              child: Container(
                width: rightDock ? 1 : double.infinity,
                height: rightDock ? double.infinity : 1,
                color: AppColors.lineStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle between a sidebar and the document workspace.
class _SidebarResizeHandle extends StatelessWidget {
  const _SidebarResizeHandle({required this.onDelta, this.onDragEnd});

  /// Callback receiving the raw horizontal pointer delta.
  final ValueChanged<double> onDelta;

  /// Callback fired when the user releases the drag, used to commit or collapse.
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
        onHorizontalDragEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        child: SignalDivider(vertical: true),
      ),
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.controller,
    required this.onShowSettings,
  });

  final AppController controller;
  final VoidCallback onShowSettings;

  @override
  Widget build(BuildContext context) {
    final hasWorkspace = controller.activeWorkspace != null;
    final showLeftContent = hasWorkspace && controller.showExplorerContent;

    final leftWidth = controller.leftSidebarWidth;
    return Row(
      children: [
        AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.curve,
          width: hasWorkspace ? 43 : 0,
          decoration: const BoxDecoration(color: Colors.transparent),
          clipBehavior: Clip.hardEdge,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 43,
            maxWidth: 43,
            child: SizedBox(
              width: 43,
              child: _ActivityRail(
                controller: controller,
                onShowSettings: onShowSettings,
              ),
            ),
          ),
        ),
        if (hasWorkspace) SignalDivider(vertical: true),
        if (hasWorkspace)
          ClipRect(
            child: SizedBox(
              width: showLeftContent ? leftWidth : 0,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: leftWidth,
                maxWidth: leftWidth,
                child: SizedBox(
                  width: leftWidth,
                  child: switch (controller.explorerView) {
                    ExplorerView.files => FileExplorerPanel(
                      controller: controller,
                    ),
                    ExplorerView.search => GlobalSearchPanel(
                      controller: controller,
                    ),
                    ExplorerView.git => GitPanel(controller: controller),
                  },
                ),
              ),
            ),
          ),
        if (showLeftContent)
          _SidebarResizeHandle(
            onDelta: (delta) =>
                controller.setLeftSidebarWidth(leftWidth + delta),
            onDragEnd: controller.finalizeLeftSidebarWidth,
          ),
        Expanded(child: DocumentArea(controller: controller)),
      ],
    );
  }
}

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({required this.controller, required this.onShowSettings});

  final AppController controller;
  final VoidCallback onShowSettings;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.activeWorkspace;
    final session = controller.activeSession;
    final hasSession = session != null;
    final isMarkdown = hasSession && session.document.isMarkdown;
    final isHtml = hasSession && session.document.isHtml;
    final showViewModes = isMarkdown || isHtml;
    return Container(
      color: AppColors.backgroundRaised,
      child: Column(
        children: [
          const SizedBox(height: 7),
          AppIconButton(
            icon: Icons.account_tree_outlined,
            tooltip: '文件',
            selected:
                controller.explorerView == ExplorerView.files &&
                controller.showExplorerContent,
            size: 34,
            iconSize: 18,
            onPressed: workspace?.isDirectory == true
                ? controller.toggleFiles
                : controller.toggleLeftSidebar,
          ),
          const SizedBox(height: 4),
          AppIconButton(
            icon: Icons.manage_search_rounded,
            tooltip: '全局搜索',
            selected:
                controller.explorerView == ExplorerView.search &&
                controller.showExplorerContent,
            size: 34,
            iconSize: 19,
            onPressed: controller.toggleGlobalSearch,
          ),
          const SizedBox(height: 4),
          AppIconButton(
            icon: Icons.commit_rounded,
            tooltip: 'Git',
            selected:
                controller.explorerView == ExplorerView.git &&
                controller.showExplorerContent,
            size: 34,
            iconSize: 18,
            accent: AppColors.acid,
            onPressed: controller.toggleGit,
          ),
          const SizedBox(height: 4),
          AppIconButton(
            icon: Icons.terminal_rounded,
            tooltip: '终端',
            selected: controller.showTerminal,
            size: 34,
            iconSize: 18,
            onPressed: controller.toggleTerminal,
          ),
          const Spacer(),
          if (showViewModes) ...[
            AppIconButton(
              icon: Icons.edit_outlined,
              tooltip: '编辑',
              selected: hasSession && session.viewMode == MarkdownViewMode.edit,
              size: 34,
              iconSize: 17,
              onPressed: hasSession
                  ? () => session.setViewMode(MarkdownViewMode.edit)
                  : null,
            ),
            const SizedBox(height: 4),
            AppIconButton(
              icon: Icons.vertical_split_outlined,
              tooltip: '分屏',
              selected:
                  hasSession && session.viewMode == MarkdownViewMode.split,
              size: 34,
              iconSize: 17,
              onPressed: hasSession
                  ? () => session.setViewMode(MarkdownViewMode.split)
                  : null,
            ),
            const SizedBox(height: 4),
            AppIconButton(
              icon: Icons.visibility_outlined,
              tooltip: '预览',
              selected:
                  hasSession && session.viewMode == MarkdownViewMode.preview,
              size: 34,
              iconSize: 17,
              onPressed: hasSession
                  ? () => session.setViewMode(MarkdownViewMode.preview)
                  : null,
            ),
            const SizedBox(height: 4),
          ],
          if (hasSession) ...[
            AppIconButton(
              icon: Icons.wrap_text_rounded,
              tooltip: session.wordWrap ? '关闭自动换行' : '开启自动换行',
              selected: session.wordWrap,
              size: 34,
              iconSize: 17,
              onPressed: session.toggleWordWrap,
            ),
            const SizedBox(height: 4),
          ],
          if (isMarkdown) ...[
            AppIconButton(
              icon: Icons.keyboard_double_arrow_right_rounded,
              tooltip: controller.showOutline ? '收起目录' : '展开目录',
              selected: controller.showOutline,
              size: 34,
              iconSize: 17,
              onPressed: controller.toggleRightSidebar,
            ),
            const SizedBox(height: 4),
          ],
          if (isHtml) ...[
            AppIconButton(
              icon: Icons.language_rounded,
              tooltip: '在 Chrome 中打开',
              size: 34,
              iconSize: 17,
              onPressed: controller.openActiveHtmlInChrome,
            ),
            const SizedBox(height: 4),
          ],
          AppIconButton(
            icon: controller.showExplorerContent
                ? Icons.keyboard_double_arrow_left_rounded
                : Icons.keyboard_double_arrow_right_rounded,
            tooltip: controller.showExplorerContent ? '收起侧栏' : '展开侧栏',
            size: 34,
            iconSize: 17,
            onPressed: controller.toggleLeftSidebar,
          ),
          const SizedBox(height: 4),
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: '设置',
            size: 34,
            iconSize: 17,
            onPressed: onShowSettings,
          ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final fullscreen = controller.isFullscreen;
    // In fullscreen the traffic lights slide off-screen and the title bar
    // belongs to the app, so we show the brand from the very left edge.
    // Windowed, the 70 px slot is reserved for the system traffic lights
    // and the workspace tabs take over from there.
    final leftPad = Platform.isMacOS ? (fullscreen ? 12.0 : 70.0) : 12.0;
    return Container(
      height: 48,
      color: AppColors.backgroundRaised,
      padding: EdgeInsets.only(left: leftPad, right: 10),
      child: Row(
        children: [
          if (fullscreen)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  Image.asset(
                    'assets/icon/nexora-icon-1024.png',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Nexora',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: controller.workspaces.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: controller.workspaces.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 5),
                    itemBuilder: (context, index) {
                      final workspace = controller.workspaces[index];
                      return _WorkspaceTab(
                        workspace: workspace,
                        selected: index == controller.activeWorkspaceIndex,
                        dirty: controller.workspaceHasDirtyDocuments(workspace),
                        onSelect: () => controller.selectWorkspace(index),
                        onClose: () => _closeWorkspace(
                          context,
                          controller,
                          index,
                          workspace,
                        ),
                      );
                    },
                  ),
          ),
          if (controller.busy)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.signal,
              ),
            )
          else ...[
            AppIconButton(
              icon: Icons.note_add_outlined,
              tooltip: '打开文件',
              size: 34,
              iconSize: 17,
              onPressed: controller.openFiles,
            ),
            const SizedBox(width: 3),
            AppIconButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: '打开文件夹',
              selected: controller.workspaces.isEmpty,
              size: 34,
              iconSize: 18,
              onPressed: controller.openDirectories,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _closeWorkspace(
    BuildContext context,
    AppController controller,
    int index,
    WorkspaceItem workspace,
  ) async {
    if (!controller.workspaceHasDirtyDocuments(workspace)) {
      await controller.closeWorkspace(index, force: true);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭工作区'),
        content: Text('${workspace.name} 中存在未保存的修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (discard == true) await controller.closeWorkspace(index, force: true);
  }
}

class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    required this.workspace,
    required this.selected,
    required this.dirty,
    required this.onSelect,
    required this.onClose,
  });

  final WorkspaceItem workspace;
  final bool selected;
  final bool dirty;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          width: 168,
          height: 40,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.signal.withValues(alpha: 0.032)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              // 与右侧关闭按钮槽位等宽，让图标+文字整体在 tab 内居中。
              const SizedBox(width: 28),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.workspace.isDirectory
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                      size: 15,
                      color: widget.selected
                          ? AppColors.signal
                          : AppColors.textDim,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        widget.workspace.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.selected
                              ? AppColors.text
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 28,
                child: widget.dirty && !_hovered
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : Center(
                        child: AppIconButton(
                          icon: Icons.close_rounded,
                          tooltip: '关闭工作区',
                          selected: widget.selected,
                          size: 24,
                          iconSize: 12,
                          onPressed: widget.onClose,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
