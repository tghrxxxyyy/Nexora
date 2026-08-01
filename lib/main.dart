import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_theme.dart';
import 'models/workspace_item.dart';
import 'services/mermaid_bundle.dart';
import 'state/app_controller.dart';
import 'widgets/app_shell.dart';
import 'widgets/settings_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexoraApp());
}

class NexoraApp extends StatefulWidget {
  const NexoraApp({super.key});

  @override
  State<NexoraApp> createState() => _NexoraAppState();
}

class _NexoraAppState extends State<NexoraApp> {
  static const _statusMenuChannel = MethodChannel(
    'com.xuyu.nexora/status_menu',
  );

  final AppController _controller = AppController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycleListener;
  String _statusMenuSnapshot = '';
  bool _statusMenuRetryPending = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    _controller.addListener(_syncStatusMenu);
    if (Platform.isMacOS) {
      _statusMenuChannel.setMethodCallHandler(_handleStatusMenuCall);
    }
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    await _controller.restoreSession();
    await _syncStatusMenu();
    _pushWindowAppearance();
    unawaited(MermaidBundle.script());
  }

  /// Pushes the theme color to the native NSWindow so the chrome stops
  /// flashing white during the brief window between app launch and the
  /// first markdown preview mounting.
  void _pushWindowAppearance() {
    if (!Platform.isMacOS) return;
    final argb = AppColors.background.toARGB32();
    const MethodChannel('com.xuyu.nexora/webview_appearance')
        .invokeMethod<bool>('setBaseColor', <String, dynamic>{
      'r': ((argb >> 16) & 0xff) / 255.0,
      'g': ((argb >> 8) & 0xff) / 255.0,
      'b': (argb & 0xff) / 255.0,
      'a': ((argb >> 24) & 0xff) / 255.0,
    }).catchError((_) => false);
  }

  Future<void> _handleStatusMenuCall(MethodCall call) async {
    if (call.method == 'requestRecentDocuments') {
      await _syncStatusMenu();
      return;
    }
    if (call.method != 'openRecentDocument') return;
    final path = call.arguments;
    if (path is! String || path.isEmpty) return;
    await _controller.openPath(path);
  }

  Future<void> _syncStatusMenu() async {
    if (!Platform.isMacOS) return;
    final documents = _controller.recentItems
        .where((item) => item.isFile)
        .take(4)
        .map((item) => {'name': item.name, 'path': item.path})
        .toList(growable: false);
    final snapshot = documents
        .map((document) => '${document['path']}\u0000${document['name']}')
        .join('\u0001');
    if (snapshot == _statusMenuSnapshot) return;
    try {
      await _statusMenuChannel.invokeMethod<void>(
        'setRecentDocuments',
        documents,
      );
      _statusMenuSnapshot = snapshot;
    } on MissingPluginException {
      if (_statusMenuRetryPending) return;
      _statusMenuRetryPending = true;
      Future<void>.delayed(const Duration(milliseconds: 400), () async {
        _statusMenuRetryPending = false;
        await _syncStatusMenu();
      });
    }
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
    _controller.removeListener(_syncStatusMenu);
    if (Platform.isMacOS) {
      _statusMenuChannel.setMethodCallHandler(null);
    }
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
        title: 'Nexora',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(_controller.currentTheme),
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(_controller.fontScale),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    final shell = AppShell(
      controller: _controller,
      onShowSettings: _showSettings,
    );
    if (!Platform.isMacOS) return shell;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Nexora',
          menus: [
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformMenuItem(label: '设置...', onSelected: _showSettings),
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

  void _showSettings() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(controller: _controller),
    );
  }
}

enum _ExitDecision { cancel, discard, save }
