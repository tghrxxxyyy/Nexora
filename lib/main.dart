import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_theme.dart';
import 'models/workspace_item.dart';
import 'state/app_controller.dart';
import 'widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XFileApp());
}

class XFileApp extends StatefulWidget {
  const XFileApp({super.key});

  @override
  State<XFileApp> createState() => _XFileAppState();
}

class _XFileAppState extends State<XFileApp> {
  final AppController _controller = AppController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    unawaited(_controller.restoreSession());
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (!_controller.hasDirtyDocuments) {
      await _controller.flushSession();
      return AppExitResponse.exit;
    }
    final context = _navigatorKey.currentContext;
    if (context == null) return AppExitResponse.cancel;
    final decision = await showDialog<_ExitDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('存在未保存的修改'),
        content: const Text('关闭前保存全部文件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitDecision.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitDecision.discard),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ExitDecision.save),
            child: const Text('全部保存'),
          ),
        ],
      ),
    );
    if (decision == _ExitDecision.discard) {
      await _controller.flushSession();
      return AppExitResponse.exit;
    }
    if (decision == _ExitDecision.save) {
      final saved = await _controller.saveAllDocuments();
      if (saved) await _controller.flushSession();
      return saved ? AppExitResponse.exit : AppExitResponse.cancel;
    }
    return AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'X-File',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_controller.themeMode),
        home: _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    final shell = AppShell(controller: _controller);
    if (!Platform.isMacOS) return shell;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'x-file',
          menus: [
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '文件',
          menus: [
            PlatformMenuItem(
              label: '打开文件',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: _controller.openFiles,
            ),
            PlatformMenuItem(
              label: '打开文件夹',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ),
              onSelected: _controller.openDirectories,
            ),
            PlatformMenu(
              label: '最近打开',
              menus: _controller.recentItems.isEmpty
                  ? const [PlatformMenuItem(label: '暂无最近项目')]
                  : _controller.recentItems
                        .map(
                          (item) => PlatformMenuItem(
                            label: _recentLabel(item),
                            onSelected: () => _controller.openRecent(item),
                          ),
                        )
                        .toList(growable: false),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '保存',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                  ),
                  onSelected: _controller.saveActiveDocument,
                ),
                PlatformMenuItem(
                  label: '在终端中打开当前目录',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyT,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: _controller.toggleTerminal,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '编辑',
          menus: [
            PlatformMenuItem(
              label: '查找',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
              onSelected: _controller.openCurrentFileFind,
            ),
            PlatformMenuItem(
              label: '全局查找',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                shift: true,
              ),
              onSelected: _controller.showGlobalSearch,
            ),
            PlatformMenuItem(
              label: '全局替换',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyH,
                meta: true,
                shift: true,
              ),
              onSelected: _controller.showGlobalReplace,
            ),
          ],
        ),
        PlatformMenu(
          label: '视图',
          menus: [
            PlatformMenuItem(
              label: '切换侧栏',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: true,
              ),
              onSelected: _controller.toggleLeftSidebar,
            ),
          ],
        ),
        const PlatformMenu(
          label: '窗口',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
      child: shell,
    );
  }

  String _recentLabel(WorkspaceItem item) {
    final parent = p.basename(p.dirname(item.path));
    return parent.isEmpty ? item.name : '${item.name}  -  $parent';
  }
}

enum _ExitDecision { cancel, discard, save }
