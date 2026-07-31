import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/workspace_item.dart';
import '../state/app_controller.dart';
import 'document_area.dart';
import 'file_sidebar.dart';
import 'global_search_panel.dart';
import 'outline_sidebar.dart';
import 'status_bar.dart';
import 'terminal_panel.dart';
import 'ui_primitives.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.controller, super.key});

  final AppController controller;

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
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.closeCurrentFileFind();
      return true;
    }
    if (!HardwareKeyboard.instance.isMetaPressed) return false;
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      controller.openCurrentFileFind();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            controller.saveActiveDocument,
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
                      const SignalDivider(),
                      if (controller.activeWorkspace != null) ...[
                        SizedBox(
                          height: 43,
                          child: DocumentToolbar(controller: controller),
                        ),
                        const SignalDivider(),
                      ],
                      Expanded(child: _WorkspaceBody(controller: controller)),
                      if (controller.showTerminal) ...[
                        const SignalDivider(),
                        AnimatedContainer(
                          duration: AppMotion.standard,
                          curve: AppMotion.curve,
                          height: 200,
                          child: TerminalPanel(
                            session: controller.terminalSession!,
                          ),
                        ),
                      ],
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
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hasWorkspace = controller.activeWorkspace != null;
    final showLeftContent = hasWorkspace && controller.showExplorerContent;
    final showRightContent = hasWorkspace && controller.showOutline;

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
              child: _ActivityRail(controller: controller),
            ),
          ),
        ),
        if (hasWorkspace) const SignalDivider(vertical: true),
        if (hasWorkspace)
          AnimatedContainer(
            duration: AppMotion.standard,
            curve: AppMotion.curve,
            width: showLeftContent ? 252 : 0,
            decoration: const BoxDecoration(color: Colors.transparent),
            clipBehavior: Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 252,
              maxWidth: 252,
              child: SizedBox(
                width: 252,
                child: controller.explorerView == ExplorerView.files
                    ? FileExplorerPanel(controller: controller)
                    : GlobalSearchPanel(controller: controller),
              ),
            ),
          ),
        if (showLeftContent) const SignalDivider(vertical: true),
        Expanded(child: DocumentArea(controller: controller)),
        if (showRightContent) const SignalDivider(vertical: true),
        AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.curve,
          width: showRightContent ? 226 : 0,
          decoration: const BoxDecoration(color: Colors.transparent),
          clipBehavior: Clip.hardEdge,
          child: OverflowBox(
            alignment: Alignment.topRight,
            minWidth: 226,
            maxWidth: 226,
            child: SizedBox(
              width: 226,
              child: OutlinePanel(controller: controller),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.activeWorkspace;
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
                ? controller.showFiles
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
            onPressed: controller.showGlobalSearch,
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
          AppIconButton(
            icon: controller.showExplorerContent
                ? Icons.keyboard_double_arrow_left_rounded
                : Icons.keyboard_double_arrow_right_rounded,
            tooltip: controller.showExplorerContent ? '收起侧栏' : '展开侧栏',
            size: 34,
            iconSize: 17,
            onPressed: controller.toggleLeftSidebar,
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
    return Container(
      height: 54,
      color: AppColors.backgroundRaised,
      padding: EdgeInsets.only(left: Platform.isMacOS ? 78 : 12, right: 10),
      child: Row(
        children: [
          Expanded(
            child: controller.workspaces.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
          height: 36,
          padding: const EdgeInsets.fromLTRB(9, 0, 4, 0),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.signal.withValues(alpha: 0.085)
                : _hovered
                ? AppColors.signal.withValues(alpha: 0.032)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(
                widget.workspace.isDirectory
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                size: 15,
                color: widget.selected ? AppColors.signal : AppColors.textDim,
              ),
              const SizedBox(width: 7),
              Expanded(
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
              if (widget.dirty && !_hovered)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                )
              else
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭工作区',
                  size: 24,
                  iconSize: 12,
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
