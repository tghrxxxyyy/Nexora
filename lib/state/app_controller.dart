import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/document_model.dart';
import '../models/file_change_event.dart';
import '../models/file_node.dart';
import '../models/git_commit.dart';
import '../models/git_diff.dart';
import '../models/search_models.dart';
import '../models/split_layout.dart';
import '../models/terminal_layout.dart';
import '../models/workspace_item.dart';
import '../services/file_icon_resolver.dart';
import '../services/file_picker_service.dart';
import '../services/app_session_store.dart';
import '../services/file_system_service.dart';
import '../services/file_watch_service.dart';
import '../services/git_service.dart';
import '../services/global_search_service.dart';
import 'editor_session.dart';
import 'icon_theme_registry.dart';
import 'theme_registry.dart';
import 'terminal_workspace_controller.dart';

enum ExplorerView { files, search, git }

enum AppMessageTone { neutral, success, warning, error }

/// How a row in the file explorer responds to hover: a flat highlight bar or
/// the scale-up "pop out" effect.
enum FileTreeHoverMode { highlight, scale }

class AppController extends ChangeNotifier {
  AppController({
    this._pickerService = const FilePickerService(),
    this._fileSystemService = const FileSystemService(),
    FileWatchService? watchService,
    this._searchService = const GlobalSearchService(),
    this._sessionStore = const AppSessionStore(),
  }) : _watchService = watchService ?? FileWatchService() {
    terminalWorkspace.addListener(_onTerminalWorkspaceChanged);
    _watchSubscription = _watchService.changes.listen(
      _onFileChanged,
      onError: (Object error, StackTrace stackTrace) {
        showMessage('文件监听异常', tone: AppMessageTone.error);
      },
    );
    setActiveFileIconResolver(currentIconTheme.resolver);
    _setupWindowChannel();
  }

  void _setupWindowChannel() {
    if (!Platform.isMacOS) return;
    const channel = MethodChannel('com.xuyu.nexora/window');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'fullscreenChanged') {
        final next = call.arguments == true;
        if (_isFullscreen == next) return;
        _isFullscreen = next;
        notifyListeners();
      }
    });
  }

  final FilePickerService _pickerService;
  final FileSystemService _fileSystemService;
  final FileWatchService _watchService;
  final GlobalSearchService _searchService;
  final AppSessionStore _sessionStore;
  final TerminalWorkspaceController terminalWorkspace =
      TerminalWorkspaceController();
  final ThemeRegistry _themeRegistry = ThemeRegistry();
  final IconThemeRegistry _iconThemeRegistry = IconThemeRegistry();
  late final StreamSubscription<FileChangeEvent> _watchSubscription;

  final List<WorkspaceItem> _workspaces = [];
  final List<WorkspaceItem> _recentItems = [];
  final Map<String, EditorSession> _sessions = {};
  final Map<String, EditorSession> _paneSessions = {};
  final Map<String, List<String>> _workspaceDocuments = {};
  final Map<String, List<FileNode>> _directoryChildren = {};
  final Set<String> _expandedDirectories = {};
  final Set<String> _expandedFileHeadings = {};
  final Map<String, int> _watchReferences = {};
  int _activeWorkspaceIndex = -1;
  bool _leftCollapsed = false;
  bool _rightCollapsed = false;
  double _leftSidebarWidth = 252;
  double _leftSidebarAnchorWidth = 252;
  double _rightSidebarWidth = 226;
  ExplorerView _explorerView = ExplorerView.files;
  bool _busy = false;
  bool _searching = false;
  bool _globalReplaceRequested = false;
  String _currentThemeId = 'light';
  String _currentIconThemeId = IconThemeRegistry.defaultId;
  double _fontScale = 1;
  FileTreeHoverMode _fileTreeHoverMode = FileTreeHoverMode.highlight;
  String? _activeHeadingAnchor;
  SearchReport? _searchReport;
  String? _searchError;
  String? _message;
  AppMessageTone _messageTone = AppMessageTone.neutral;
  Timer? _messageTimer;
  Timer? _sessionPersistTimer;
  Future<void> _sessionWriteQueue = Future<void>.value();
  bool _restoringSession = false;
  bool _sessionRestored = false;
  int _revealRequestId = 0;
  bool _isFullscreen = false;

  final GitService _gitService = const GitService();
  GitRepoStatus? _gitStatus;
  List<GitCommit> _gitCommits = const [];
  String? _gitSelectedSha;
  List<GitFileChange> _gitFileChanges = const [];
  GitDiffTarget? _gitActiveDiff;
  bool _gitLoading = false;
  String? _gitError;

  List<WorkspaceItem> get workspaces => List.unmodifiable(_workspaces);
  List<WorkspaceItem> get recentItems => List.unmodifiable(_recentItems);
  Map<String, EditorSession> get sessions => Map.unmodifiable(_sessions);
  Set<String> get expandedDirectories => Set.unmodifiable(_expandedDirectories);
  Set<String> get expandedFileHeadings =>
      Set.unmodifiable(_expandedFileHeadings);
  int get activeWorkspaceIndex => _activeWorkspaceIndex;
  bool get leftCollapsed => _leftCollapsed;
  bool get rightCollapsed => _rightCollapsed;
  double get leftSidebarWidth => _leftSidebarWidth;
  double get rightSidebarWidth => _rightSidebarWidth;
  bool get showTerminal => terminalWorkspace.visible;
  String get terminalWorkingDirectory {
    final workspace = activeWorkspace;
    if (workspace == null) return Platform.environment['HOME'] ?? '/';
    return workspace.isDirectory ? workspace.path : p.dirname(workspace.path);
  }

  ExplorerView get explorerView => _explorerView;
  bool get busy => _busy;
  bool get searching => _searching;
  bool get globalReplaceRequested => _globalReplaceRequested;

  GitRepoStatus? get gitStatus => _gitStatus;
  List<GitCommit> get gitCommits => _gitCommits;
  String? get gitSelectedSha => _gitSelectedSha;
  List<GitFileChange> get gitFileChanges => _gitFileChanges;
  GitDiffTarget? get gitActiveDiff => _gitActiveDiff;
  bool get gitLoading => _gitLoading;
  String? get gitError => _gitError;

  bool get isFullscreen => _isFullscreen;

  AppThemeDefinition get currentTheme {
    return _themeRegistry.find(_currentThemeId) ??
        AppColors.builtinThemes.first;
  }

  String get currentThemeId => _currentThemeId;

  List<AppThemeDefinition> get availableThemes => _themeRegistry.themes;

  FileIconTheme get currentIconTheme {
    return _iconThemeRegistry.find(_currentIconThemeId) ??
        _iconThemeRegistry.themes.first;
  }

  String get currentIconThemeId => _currentIconThemeId;

  List<FileIconTheme> get availableIconThemes => _iconThemeRegistry.themes;

  /// Backwards-compatible view for widgets that still branch on light/dark.
  /// Derived from the current palette's background luminance so any imported
  /// theme resolves to the right brightness without callers being aware of ids.
  AppThemeMode get themeMode {
    return currentTheme.palette.background.computeLuminance() < 0.5
        ? AppThemeMode.dark
        : AppThemeMode.light;
  }

  double get fontScale => _fontScale;
  FileTreeHoverMode get fileTreeHoverMode => _fileTreeHoverMode;
  String? get activeHeadingAnchor => _activeHeadingAnchor;
  SearchReport? get searchReport => _searchReport;
  String? get searchError => _searchError;
  String? get message => _message;
  AppMessageTone get messageTone => _messageTone;
  bool get hasDirtyDocuments =>
      _sessions.values.any((session) => session.document.isDirty);

  /// Monotonic counter bumped whenever the sidebar should scroll to reveal the
  /// active file. Watched by [_FileExplorerPanelState] to trigger a post-frame
  /// scroll after the rebuilt tree is committed.
  int get revealRequestId => _revealRequestId;

  Future<void> restoreSession() async {
    if (_sessionRestored || _restoringSession) return;
    _restoringSession = true;
    try {
      await _themeRegistry.loadImported();
      final state = await _sessionStore.read();
      if (state == null) return;
      final workspaces = state['workspaces'];
      if (workspaces is! List) return;
      _leftCollapsed = state['leftCollapsed'] == true;
      _rightCollapsed = state['rightCollapsed'] == true;
      _leftSidebarWidth = state['leftSidebarWidth'] is num
          ? (state['leftSidebarWidth'] as num)
                .toDouble()
                .clamp(180.0, 480.0)
                .toDouble()
          : 252;
      _leftSidebarAnchorWidth = _leftSidebarWidth;
      _rightSidebarWidth = state['rightSidebarWidth'] is num
          ? (state['rightSidebarWidth'] as num)
                .toDouble()
                .clamp(160.0, 420.0)
                .toDouble()
          : 226;
      _explorerView = ExplorerView.values.firstWhere(
        (v) => v.name == state['explorerView'],
        orElse: () => ExplorerView.files,
      );
      terminalWorkspace.restorePreferences(
        dock: state['terminalDock'] == TerminalDock.right.name
            ? TerminalDock.right
            : TerminalDock.bottom,
        bottomExtent: state['terminalBottomExtent'] is num
            ? (state['terminalBottomExtent'] as num).toDouble()
            : 260,
        rightExtent: state['terminalRightExtent'] is num
            ? (state['terminalRightExtent'] as num).toDouble()
            : 420,
      );
      // Theme: prefer the new themeId; fall back to legacy themeMode string; else default.
      final themeIdValue = state['themeId'];
      final legacyMode = state['themeMode'];
      _currentThemeId = (themeIdValue is String && themeIdValue.isNotEmpty)
          ? themeIdValue
          : legacyMode is String && legacyMode.isNotEmpty
          ? legacyMode
          : 'light';
      final iconThemeValue = state['iconThemeId'];
      _currentIconThemeId =
          (iconThemeValue is String && iconThemeValue.isNotEmpty)
          ? iconThemeValue
          : IconThemeRegistry.defaultId;
      setActiveFileIconResolver(currentIconTheme.resolver);
      _fontScale = state['fontScale'] is num
          ? (state['fontScale'] as num).toDouble().clamp(0.85, 1.45).toDouble()
          : 1;
      _fileTreeHoverMode = FileTreeHoverMode.values.firstWhere(
        (mode) => mode.name == state['fileTreeHoverMode'],
        orElse: () => FileTreeHoverMode.highlight,
      );
      AppColors.apply(currentTheme);
      _restoreRecentItems(state['recentItems']);

      for (final value in workspaces) {
        if (value is! Map) continue;
        await _restoreWorkspace(Map<String, dynamic>.from(value));
      }

      final activeId = state['activeWorkspaceId'];
      final activeIndex = activeId is String
          ? _workspaces.indexWhere((workspace) => workspace.id == activeId)
          : -1;
      if (activeIndex >= 0) {
        _activeWorkspaceIndex = activeIndex;
      } else if (_workspaces.isNotEmpty) {
        _activeWorkspaceIndex = _workspaces.length - 1;
      }
      _syncSidebarDefaults();
    } finally {
      _restoringSession = false;
      _sessionRestored = true;
      notifyListeners();
    }
  }

  Future<void> flushSession() async {
    _sessionPersistTimer?.cancel();
    await _persistSession();
  }

  WorkspaceItem? get activeWorkspace {
    if (_activeWorkspaceIndex < 0 ||
        _activeWorkspaceIndex >= _workspaces.length) {
      return null;
    }
    return _workspaces[_activeWorkspaceIndex];
  }

  EditorSession? get activeSession {
    final path = activeWorkspace?.selectedFilePath;
    return path == null ? null : _sessions[path];
  }

  List<String> get activeDocumentPaths {
    final workspace = activeWorkspace;
    if (workspace == null) return const [];
    return List.unmodifiable(_workspaceDocuments[workspace.id] ?? const []);
  }

  List<FileNode> childrenFor(String directoryPath) {
    return _directoryChildren[_normalize(directoryPath)] ?? const [];
  }

  bool get showExplorerContent {
    final workspace = activeWorkspace;
    return !_leftCollapsed &&
        (workspace?.isDirectory == true ||
            _explorerView == ExplorerView.search ||
            _explorerView == ExplorerView.git);
  }

  bool get showOutline {
    return !_rightCollapsed && activeSession?.document.isMarkdown == true;
  }

  bool workspaceHasDirtyDocuments(WorkspaceItem workspace) {
    return (_workspaceDocuments[workspace.id] ?? const []).any(
      (path) => _sessions[path]?.document.isDirty == true,
    );
  }

  bool documentIsUsedElsewhere(String path, WorkspaceItem excludedWorkspace) {
    return _workspaces.any(
      (workspace) =>
          workspace != excludedWorkspace &&
          (_workspaceDocuments[workspace.id] ?? const []).contains(path),
    );
  }

  Future<void> openFiles() async {
    await _runBusy(() async {
      final items = await _pickerService.pickFiles();
      await _addWorkspaces(items);
    });
  }

  Future<void> openDirectories() async {
    await _runBusy(() async {
      final items = await _pickerService.pickDirectories();
      await _addWorkspaces(items);
    });
  }

  Future<void> openPath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await _addWorkspaces([
        WorkspaceItem(
          path: _normalize(path),
          name: p.basename(path),
          type: WorkspaceItemType.directory,
        ),
      ]);
    } else if (type == FileSystemEntityType.file) {
      final workspace = activeWorkspace;
      if (workspace?.isDirectory == true && p.isWithin(workspace!.path, path)) {
        await openDocument(path);
      } else {
        await _addWorkspaces([
          WorkspaceItem(
            path: _normalize(path),
            name: p.basename(path),
            type: WorkspaceItemType.file,
          ),
        ]);
      }
    }
  }

  Future<void> _addWorkspaces(Iterable<WorkspaceItem> items) async {
    var lastIndex = -1;
    for (final item in items) {
      _recordRecent(item);
      final existingIndex = _workspaces.indexWhere(
        (workspace) => workspace.id == item.id,
      );
      if (existingIndex >= 0) {
        lastIndex = existingIndex;
        continue;
      }

      final workspace = item.isFile
          ? item.copyWith(selectedFilePath: item.path)
          : item;
      _workspaces.add(workspace);
      _workspaceDocuments[workspace.id] = [];
      lastIndex = _workspaces.length - 1;
      await _retainWatch(workspace.path);

      if (workspace.isDirectory) {
        await _loadDirectory(workspace.path, expand: true);
      } else {
        await _openDocumentFor(workspace, workspace.path);
      }
    }

    if (lastIndex >= 0) {
      _activeWorkspaceIndex = lastIndex;
      _syncSidebarDefaults();
      notifyListeners();
      await _persistSession();
    }
  }

  void selectWorkspace(int index) {
    if (index < 0 || index >= _workspaces.length) return;
    _activeWorkspaceIndex = index;
    _activeHeadingAnchor = null;
    _gitSelectedSha = null;
    _gitActiveDiff = null;
    _gitFileChanges = const [];
    _syncSidebarDefaults();
    notifyListeners();
    _scheduleSessionSave();
    if (_explorerView == ExplorerView.git && !_leftCollapsed) {
      refreshGitState();
    }
  }

  Future<void> closeWorkspace(int index, {bool force = false}) async {
    if (index < 0 || index >= _workspaces.length) return;
    final workspace = _workspaces[index];
    if (!force && workspaceHasDirtyDocuments(workspace)) return;

    await _releaseWatch(workspace.path);
    final documentPaths = List<String>.from(
      _workspaceDocuments.remove(workspace.id) ?? const [],
    );
    // Drop any pane clones belonging to this workspace's split tree before
    // tearing down the workspace itself.
    final split = workspace.split;
    if (split != null) {
      for (final leaf in split.leaves) {
        _paneSessions.remove(leaf.paneId)?.dispose();
      }
    }
    _workspaces.removeAt(index);

    for (final path in documentPaths) {
      if (!documentIsUsedElsewhere(path, workspace)) {
        _sessions.remove(path)?.dispose();
      }
    }

    if (workspace.isDirectory) {
      _directoryChildren.removeWhere(
        (path, value) =>
            path == workspace.path || p.isWithin(workspace.path, path),
      );
      _expandedDirectories.removeWhere(
        (path) => path == workspace.path || p.isWithin(workspace.path, path),
      );
    }

    if (_workspaces.isEmpty) {
      _activeWorkspaceIndex = -1;
    } else if (_activeWorkspaceIndex > index) {
      _activeWorkspaceIndex--;
    } else if (_activeWorkspaceIndex >= _workspaces.length) {
      _activeWorkspaceIndex = _workspaces.length - 1;
    }
    _syncSidebarDefaults();
    notifyListeners();
    await _persistSession();
  }

  Future<void> openDocument(String path) async {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    await _runBusy(() => _openDocumentFor(workspace, path));
    if (activeSession?.document.path == _normalize(path)) {
      _recordRecent(
        WorkspaceItem(
          path: _normalize(path),
          name: p.basename(path),
          type: WorkspaceItemType.file,
        ),
      );
      notifyListeners();
    }
    await _persistSession();
  }

  Future<void> openRecent(WorkspaceItem item) async {
    final entityType = await FileSystemEntity.type(
      item.path,
      followLinks: false,
    );
    final matches = item.isDirectory
        ? entityType == FileSystemEntityType.directory
        : entityType == FileSystemEntityType.file;
    if (!matches) {
      showMessage('最近项目已不存在', tone: AppMessageTone.warning);
      return;
    }
    await openPath(item.path);
  }

  Future<void> openActiveInTerminal() async {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final directory = workspace.isDirectory
        ? workspace.path
        : p.dirname(workspace.path);
    if (!Directory(directory).existsSync()) {
      showMessage('目录不存在，无法打开终端', tone: AppMessageTone.error);
      return;
    }
    try {
      if (Platform.isMacOS) {
        final command = 'cd ${_shellQuote(directory)}';
        final script =
            'tell application "Terminal"\n'
            'activate\n'
            'do script ${_appleScriptString(command)}\n'
            'end tell';
        await Process.run('osascript', ['-e', script]);
      } else if (Platform.isWindows) {
        final command = 'cd /d "${directory.replaceAll('"', '""')}"';
        await Process.run('cmd', [
          '/c',
          'start',
          '',
          'cmd',
          '/K',
          command,
        ], runInShell: true);
      } else {
        await Process.run('x-terminal-emulator', [
          '--working-directory=$directory',
        ]);
      }
      showMessage(
        '已在终端打开 ${p.basename(directory)}',
        tone: AppMessageTone.success,
      );
    } on ProcessException {
      showMessage('无法启动系统终端', tone: AppMessageTone.error);
    }
  }

  /// Copies the absolute path of [path] to the system clipboard.
  Future<void> copyAbsolutePath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    showMessage('已复制绝对路径', tone: AppMessageTone.success);
  }

  /// Copies the path of [path] relative to the owning workspace root. Falls
  /// back to the absolute path when the file lives outside any directory
  /// workspace (e.g. a loose file opened via "open file").
  Future<void> copyRelativePath(String path) async {
    final normalizedPath = _normalize(path);
    final root = _containingWorkspaceRoot(normalizedPath);
    final text = root != null
        ? p.relative(normalizedPath, from: root)
        : normalizedPath;
    await Clipboard.setData(ClipboardData(text: text));
    showMessage('已复制相对路径', tone: AppMessageTone.success);
  }

  /// Writes the file itself to the system clipboard (Finder/Explorer paste
  /// creates a copy). Implemented per-platform: macOS uses AppleScript against
  /// Finder, Windows PowerShell with `Set-Clipboard -LiteralPath`, Linux is a
  /// no-op for now (would need xclip with `target x-special/gnome-files`).
  Future<void> copyFileToClipboard(String path) async {
    final normalizedPath = _normalize(path);
    final entity = FileSystemEntity.typeSync(normalizedPath);
    if (entity != FileSystemEntityType.file &&
        entity != FileSystemEntityType.directory) {
      showMessage('文件不存在', tone: AppMessageTone.error);
      return;
    }
    try {
      if (Platform.isMacOS) {
        final script =
            'tell application "Finder" to set the clipboard to '
            '(file (POSIX file ${_appleScriptString(normalizedPath)}) as alias)';
        final result = await Process.run('osascript', ['-e', script]);
        if (result.exitCode != 0) {
          showMessage('复制文件失败', tone: AppMessageTone.error);
          return;
        }
      } else if (Platform.isWindows) {
        final ps = "'${normalizedPath.replaceAll("'", "''")}'";
        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Set-Clipboard -LiteralPath $ps',
        ]);
      } else {
        showMessage('当前平台不支持复制文件', tone: AppMessageTone.warning);
        return;
      }
      showMessage(
        '已复制文件 ${p.basename(normalizedPath)}',
        tone: AppMessageTone.success,
      );
    } on ProcessException {
      showMessage('复制文件失败', tone: AppMessageTone.error);
    }
  }

  /// Reveals [path] in the native file manager (Finder/Explorer). On macOS
  /// uses `open -R` which selects the file inside its parent window.
  Future<void> revealInFileManager(String path) async {
    final normalizedPath = _normalize(path);
    final exists =
        FileSystemEntity.typeSync(normalizedPath) !=
        FileSystemEntityType.notFound;
    if (!exists) {
      showMessage('文件不存在', tone: AppMessageTone.error);
      return;
    }
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', normalizedPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', normalizedPath]);
      } else {
        // No standard "reveal" flag on Linux; just open the parent directory.
        final parent = p.dirname(normalizedPath);
        await Process.run('xdg-open', [parent]);
      }
    } on ProcessException {
      showMessage('无法打开文件管理器', tone: AppMessageTone.error);
    }
  }

  /// Returns the absolute path of the directory workspace that contains
  /// [absolutePath], or null when the path is not under any directory
  /// workspace. Used to compute relative paths.
  String? _containingWorkspaceRoot(String absolutePath) {
    for (final ws in _workspaces) {
      if (ws.isDirectory && p.isWithin(ws.path, absolutePath)) {
        return ws.path;
      }
    }
    return null;
  }

  Future<void> _openDocumentFor(WorkspaceItem workspace, String path) async {
    final normalizedPath = _normalize(path);
    var session = _sessions[normalizedPath];
    if (session == null) {
      final document = await _fileSystemService.readDocument(normalizedPath);
      session = _createSession(document);
      _sessions[normalizedPath] = session;
    }

    final documents = _workspaceDocuments[workspace.id] ??= [];
    if (!documents.contains(normalizedPath)) documents.add(normalizedPath);
    final workspaceIndex = _workspaces.indexOf(workspace);
    _activeWorkspaceIndex = workspaceIndex;
    // When a split is active, route the open through the pane that currently
    // hosts the workspace's selectedFilePath (or the primary-most pane if the
    // selected path isn't in any pane yet) so the new file lands as a tab in
    // the focused pane without disturbing sibling panes.
    final activeSplit = workspace.split;
    if (activeSplit != null) {
      final targetPaneId =
          _paneIdContainingPath(activeSplit, workspace.selectedFilePath) ??
          activeSplit.leaves.first.paneId;
      await addToPaneDocument(targetPaneId, normalizedPath);
      // addToPaneDocument already updated workspace.selectedFilePath + split.
    } else if (workspaceIndex >= 0) {
      _workspaces[workspaceIndex] = workspace.copyWith(
        selectedFilePath: normalizedPath,
      );
    }
    notifyListeners();
    await revealPathInWorkspace(normalizedPath);
  }

  void selectDocument(String path) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final normalizedPath = _normalize(path);
    if (!(_workspaceDocuments[workspace.id] ?? const []).contains(
      normalizedPath,
    )) {
      return;
    }
    // When a split is active, route the click through the pane that contains
    // (or most recently hosted) the path — switching its active tab rather
    // than replacing the pane's contents.
    final split = workspace.split;
    if (split != null) {
      final paneId =
          _paneIdContainingPath(split, normalizedPath) ??
          _paneIdContainingPath(split, workspace.selectedFilePath) ??
          split.leaves.first.paneId;
      // Make sure the path is a tab in that pane (push if missing) and active.
      unawaited(addToPaneDocument(paneId, normalizedPath));
      // Fall through to update selectedFilePath / record recent — split is
      // already up to date via addToPaneDocument.
    } else {
      _workspaces[_activeWorkspaceIndex] = workspace.copyWith(
        selectedFilePath: normalizedPath,
      );
    }
    _recordRecent(
      WorkspaceItem(
        path: normalizedPath,
        name: p.basename(normalizedPath),
        type: WorkspaceItemType.file,
      ),
    );
    _activeHeadingAnchor = null;
    _gitActiveDiff = null;
    notifyListeners();
    _scheduleSessionSave();
    unawaited(revealPathInWorkspace(normalizedPath));
  }

  /// Finds the paneId whose openPaths contains [path]. Returns null when [path]
  /// isn't open in any pane (e.g. null input, or path not yet tabbed).
  String? _paneIdContainingPath(SplitNode? node, String? path) {
    if (node == null || path == null) return null;
    for (final leaf in node.leaves) {
      if (leaf.openPaths.contains(path)) return leaf.paneId;
    }
    return null;
  }

  /// Expands every ancestor directory of [filePath] inside the owning
  /// workspace and bumps [revealRequestId] so the sidebar can scroll the row
  /// into view. No-op when the path is outside any directory workspace.
  Future<void> revealPathInWorkspace(String filePath) async {
    final normalizedPath = _normalize(filePath);
    WorkspaceItem? owner;
    for (final ws in _workspaces) {
      if (ws.isDirectory && p.isWithin(ws.path, normalizedPath)) {
        owner = ws;
        break;
      }
    }
    if (owner == null) return;

    String? current = p.dirname(normalizedPath);
    while (current != null &&
        current.isNotEmpty &&
        p.isWithin(owner.path, current)) {
      if (!_expandedDirectories.contains(current)) {
        await _loadDirectory(current, expand: true);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    _revealRequestId++;
    notifyListeners();
  }

  void closeDocument(String path, {bool force = false}) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final normalizedPath = _normalize(path);
    final session = _sessions[normalizedPath];
    if (!force && session?.document.isDirty == true) return;
    final documents = _workspaceDocuments[workspace.id];
    if (documents == null) return;
    final removedIndex = documents.indexOf(normalizedPath);
    if (removedIndex < 0) return;
    documents.removeAt(removedIndex);

    var selectedPath = workspace.selectedFilePath;
    if (selectedPath == normalizedPath) {
      selectedPath = documents.isEmpty
          ? null
          : documents[removedIndex.clamp(0, documents.length - 1)];
    }
    _workspaces[_activeWorkspaceIndex] = workspace.copyWith(
      selectedFilePath: selectedPath,
      clearSelectedFilePath: selectedPath == null,
    );
    if (!documentIsUsedElsewhere(normalizedPath, workspace)) {
      _sessions.remove(normalizedPath)?.dispose();
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  Future<void> toggleDirectory(String path) async {
    final normalizedPath = _normalize(path);
    if (_expandedDirectories.remove(normalizedPath)) {
      notifyListeners();
      return;
    }
    await _runBusy(() => _loadDirectory(normalizedPath, expand: true));
  }

  Future<void> toggleFileHeadings(String path) async {
    final normalizedPath = _normalize(path);
    if (_expandedFileHeadings.remove(normalizedPath)) {
      notifyListeners();
      return;
    }
    if (!_sessions.containsKey(normalizedPath)) {
      try {
        final document = await _fileSystemService.readDocument(normalizedPath);
        final session = _createSession(document);
        _sessions[normalizedPath] = session;
      } on Exception {
        return;
      }
    }
    _expandedFileHeadings.add(normalizedPath);
    notifyListeners();
  }

  Future<void> openAndJumpToHeading(
    String filePath,
    int lineNumber,
    String anchor,
  ) async {
    await openDocument(filePath);
    jumpToHeading(lineNumber, anchor);
  }

  Future<void> refreshActiveDirectory() async {
    final workspace = activeWorkspace;
    if (workspace?.isDirectory != true) return;
    await _runBusy(() async {
      final directories = _directoryChildren.keys
          .where(
            (path) =>
                path == workspace!.path || p.isWithin(workspace.path, path),
          )
          .toList();
      for (final path in directories) {
        await _loadDirectory(path);
      }
    });
  }

  Future<void> _loadDirectory(String path, {bool expand = false}) async {
    var currentPath = _normalize(path);
    while (true) {
      final children = await _fileSystemService.listDirectory(
        currentPath,
        includeHidden: true,
      );
      _directoryChildren[currentPath] = children;
      if (!expand) break;

      _expandedDirectories.add(currentPath);
      if (children.length != 1 || !children.single.isDirectory) break;
      currentPath = children.single.path;
    }
    notifyListeners();
  }

  void toggleLeftSidebar() {
    _leftCollapsed = !_leftCollapsed;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Applies a registered theme by id. Silently falls back to 'light' when the
  /// id is unknown (e.g. a deleted imported theme was the last selection).
  void setTheme(String id) {
    final theme = _themeRegistry.find(id);
    final resolved = theme ?? AppColors.builtinThemes.first;
    if (_currentThemeId == resolved.id && theme != null) return;
    _currentThemeId = resolved.id;
    AppColors.apply(resolved);
    notifyListeners();
    _scheduleSessionSave();
    if (theme == null) {
      showMessage(
        '主题 $id 不存在,已回落到 ${resolved.name}',
        tone: AppMessageTone.warning,
      );
    }
  }

  /// Switches the file icon theme by id. Falls back to the default when the
  /// id is unknown (e.g. a future id removed in a newer build).
  void setIconTheme(String id) {
    final theme = _iconThemeRegistry.find(id);
    final resolved = theme ?? _iconThemeRegistry.themes.first;
    if (_currentIconThemeId == resolved.id && theme != null) return;
    _currentIconThemeId = resolved.id;
    setActiveFileIconResolver(resolved.resolver);
    notifyListeners();
    _scheduleSessionSave();
    if (theme == null) {
      showMessage(
        '图标主题 $id 不存在,已回落到 ${resolved.name}',
        tone: AppMessageTone.warning,
      );
    }
  }

  /// Imports a theme from a JSON file path, persists it, and switches to it.
  Future<void> importTheme(String jsonPath) async {
    try {
      final source = await File(jsonPath).readAsString();
      final fallbackId = p.basenameWithoutExtension(jsonPath);
      final theme = const ThemeLoader().parse(
        source,
        fallbackId: fallbackId,
        fallbackName: fallbackId,
      );
      final persisted = await _themeRegistry.addImported(theme);
      _currentThemeId = persisted.id;
      AppColors.apply(persisted);
      notifyListeners();
      _scheduleSessionSave();
      showMessage('已导入主题 ${persisted.name}', tone: AppMessageTone.success);
    } on ThemeFormatException catch (error) {
      showMessage(error.message, tone: AppMessageTone.error);
    } on FileSystemException catch (error) {
      showMessage('读取文件失败: ${error.message}', tone: AppMessageTone.error);
    } catch (error) {
      showMessage('导入主题失败: $error', tone: AppMessageTone.error);
    }
  }

  /// Deletes an imported theme by id. Built-in themes cannot be deleted.
  /// If the deleted theme was active, falls back to 'light'.
  Future<void> deleteTheme(String id) async {
    final theme = _themeRegistry.find(id);
    if (theme == null || theme.builtIn) return;
    final removed = await _themeRegistry.remove(id);
    if (!removed) return;
    if (_currentThemeId == id) {
      _currentThemeId = 'light';
      AppColors.apply(currentTheme);
    }
    notifyListeners();
    _scheduleSessionSave();
    showMessage('已删除主题 ${theme.name}', tone: AppMessageTone.neutral);
  }

  /// Opens a file picker filtered to .json and imports the chosen file.
  Future<void> pickThemeFile() async {
    final items = await _pickerService.pickFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: '主题文件', extensions: ['json']),
      ],
    );
    if (items.isEmpty) return;
    await importTheme(items.first.path);
  }

  void setFontScale(double value) {
    final nextValue = value.clamp(0.85, 1.45).toDouble();
    if ((_fontScale - nextValue).abs() < 0.001) return;
    _fontScale = nextValue;
    notifyListeners();
    _scheduleSessionSave();
  }

  void setFileTreeHoverMode(FileTreeHoverMode mode) {
    if (_fileTreeHoverMode == mode) return;
    _fileTreeHoverMode = mode;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Shows or hides the integrated terminal for the active workspace.
  void toggleTerminal() {
    terminalWorkspace.toggle(workingDirectory: terminalWorkingDirectory);
  }

  void toggleRightSidebar() {
    _rightCollapsed = !_rightCollapsed;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Minimum sidebar width while dragging. Below this the pane is unreadable,
  /// so we hard-stop the visual shrink.
  static const double _leftSidebarMinDragWidth = 60;

  /// Drag-release threshold below which the sidebar fully collapses, mirroring
  /// [toggleLeftSidebar]. Values at or above this are kept as the new width.
  static const double _leftSidebarCollapseThreshold = 140;

  void setLeftSidebarWidth(double value) {
    final next = value.clamp(_leftSidebarMinDragWidth, 480.0).toDouble();
    if ((_leftSidebarWidth - next).abs() < 0.001) return;
    _leftSidebarWidth = next;
    if (next >= _leftSidebarCollapseThreshold) {
      _leftSidebarAnchorWidth = next;
    }
    notifyListeners();
  }

  /// Called when the user releases the sidebar drag handle. If the live width
  /// has been dragged below the collapse threshold, the sidebar folds away just
  /// like pressing Cmd+B, and the prior width is restored on next expand.
  void finalizeLeftSidebarWidth() {
    if (_leftSidebarWidth < _leftSidebarCollapseThreshold) {
      _leftSidebarWidth = _leftSidebarAnchorWidth;
      _leftCollapsed = true;
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  void setRightSidebarWidth(double value) {
    final next = value.clamp(160.0, 420.0).toDouble();
    if ((_rightSidebarWidth - next).abs() < 0.001) return;
    _rightSidebarWidth = next;
    notifyListeners();
    _scheduleSessionSave();
  }

  void showFiles() {
    _explorerView = ExplorerView.files;
    if (activeWorkspace?.isDirectory == true) _leftCollapsed = false;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Toggles the files explorer: collapses if it is the active, visible view;
  /// otherwise switches to files and expands the sidebar.
  void toggleFiles() {
    if (_explorerView == ExplorerView.files && !_leftCollapsed) {
      _leftCollapsed = true;
    } else {
      _explorerView = ExplorerView.files;
      if (activeWorkspace?.isDirectory == true) _leftCollapsed = false;
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  void showGlobalSearch() {
    _explorerView = ExplorerView.search;
    _leftCollapsed = false;
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Toggles global search: collapses if it is the active, visible view;
  /// otherwise switches to search and expands the sidebar.
  void toggleGlobalSearch() {
    if (_explorerView == ExplorerView.search && !_leftCollapsed) {
      _leftCollapsed = true;
    } else {
      _explorerView = ExplorerView.search;
      _leftCollapsed = false;
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  void showGlobalReplace() {
    _explorerView = ExplorerView.search;
    _leftCollapsed = false;
    _globalReplaceRequested = true;
    notifyListeners();
    _scheduleSessionSave();
  }

  void clearGlobalReplaceRequest() {
    if (!_globalReplaceRequested) return;
    _globalReplaceRequested = false;
    notifyListeners();
  }

  void showGit() {
    _explorerView = ExplorerView.git;
    _leftCollapsed = false;
    notifyListeners();
    _scheduleSessionSave();
    refreshGitState();
  }

  /// Toggles the git inspector: collapses if it is the active, visible view;
  /// otherwise switches to git and expands the sidebar.
  void toggleGit() {
    if (_explorerView == ExplorerView.git && !_leftCollapsed) {
      _leftCollapsed = true;
    } else {
      _explorerView = ExplorerView.git;
      _leftCollapsed = false;
    }
    notifyListeners();
    _scheduleSessionSave();
    if (!_leftCollapsed) refreshGitState();
  }

  /// Reloads branch status, commit log, and the file-level changes for the
  /// currently selected target (working tree by default). Safe to call when
  /// the active workspace is not a git repository — the panel will show an
  /// empty state.
  Future<void> refreshGitState() async {
    final workspace = activeWorkspace;
    if (workspace == null) {
      _gitStatus = null;
      _gitCommits = const [];
      _gitFileChanges = const [];
      _gitActiveDiff = null;
      _gitError = null;
      _gitLoading = false;
      notifyListeners();
      return;
    }
    final probePath = workspace.isDirectory
        ? workspace.path
        : p.dirname(workspace.path);
    _gitLoading = true;
    _gitError = null;
    notifyListeners();
    try {
      final root = await _gitService.findRepositoryRoot(probePath);
      if (root == null) {
        _gitStatus = null;
        _gitCommits = const [];
        _gitFileChanges = const [];
        _gitActiveDiff = null;
        _gitLoading = false;
        notifyListeners();
        return;
      }
      final status = await _gitService.getStatus(root);
      final commits = await _gitService.getRecentCommits(root);
      _gitStatus = status;
      _gitCommits = commits;
      if (_gitSelectedSha != null &&
          !commits.any((c) => c.sha == _gitSelectedSha)) {
        _gitSelectedSha = null;
      }
      await _loadGitFileChanges(root);
      // Active diff view is stale after a refresh — close it so the editor
      // doesn't keep showing a snapshot that may no longer match the repo.
      _gitActiveDiff = null;
      _gitLoading = false;
      notifyListeners();
    } catch (error) {
      _gitLoading = false;
      _gitError = error.toString();
      notifyListeners();
    }
  }

  /// Selects which commit's changes to inspect: `null` for the working tree
  /// (uncommitted changes), or a commit sha from [gitCommits]. Clears any
  /// active diff view since the file list underneath is about to change.
  Future<void> selectGitDiffTarget(String? sha) async {
    if (_gitSelectedSha == sha) return;
    _gitSelectedSha = sha;
    _gitActiveDiff = null;
    notifyListeners();
    final root = _gitStatus?.rootPath;
    if (root == null) return;
    try {
      await _loadGitFileChanges(root);
    } catch (error) {
      _gitError = error.toString();
    }
    notifyListeners();
  }

  /// Opens a split diff view for [path] in the editor area. The file must
  /// already be present in [gitFileChanges] for the current target.
  void selectGitFile(String path) {
    GitFileChange? change;
    for (final c in _gitFileChanges) {
      if (c.path == path) {
        change = c;
        break;
      }
    }
    if (change == null) return;
    _gitActiveDiff = GitDiffTarget(
      sha: _gitSelectedSha,
      path: change.path,
      displayName: change.displayName,
      status: change.status,
      oldPath: change.oldPath,
    );
    notifyListeners();
  }

  /// Closes the diff view in the editor area and returns to the document.
  void closeGitDiff() {
    if (_gitActiveDiff == null) return;
    _gitActiveDiff = null;
    notifyListeners();
  }

  /// Returns the parsed file change for the currently open diff, or `null`
  /// if no diff is open or the underlying data has been evicted.
  GitFileChange? lookupActiveGitFileChange() {
    final target = _gitActiveDiff;
    if (target == null) return null;
    for (final change in _gitFileChanges) {
      if (change.path == target.path) return change;
    }
    return null;
  }

  Future<void> _loadGitFileChanges(String root) async {
    final sha = _gitSelectedSha;
    _gitFileChanges = await _gitService.getFileChanges(root, sha: sha);
  }

  Future<void> saveActiveDocument({bool overwrite = false}) async {
    final session = activeSession;
    if (session == null || (!session.document.isDirty && !overwrite)) return;
    try {
      final saved = await _fileSystemService.saveDocument(
        session.document,
        overwriteExternalChanges: overwrite,
      );
      session.adoptSavedDocument(saved);
      showMessage('已保存 ${saved.name}', tone: AppMessageTone.success);
    } on ExternalFileChangeException {
      session.markExternalChange();
      showMessage('磁盘文件已变化，请选择保留版本', tone: AppMessageTone.warning);
    } on FileSystemException catch (error) {
      showMessage(error.message, tone: AppMessageTone.error);
    }
  }

  Future<bool> saveAllDocuments() async {
    for (final session in _sessions.values) {
      if (!session.document.isDirty) continue;
      try {
        final saved = await _fileSystemService.saveDocument(session.document);
        session.adoptSavedDocument(saved);
      } on ExternalFileChangeException {
        session.markExternalChange();
        showMessage(
          '${session.document.name} 在磁盘上已变化',
          tone: AppMessageTone.warning,
        );
        return false;
      } on FileSystemException catch (error) {
        showMessage(error.message, tone: AppMessageTone.error);
        return false;
      }
    }
    showMessage('全部文件已保存', tone: AppMessageTone.success);
    return true;
  }

  Future<void> reloadActiveDocument() async {
    final session = activeSession;
    if (session == null) return;
    try {
      final diskDocument = await _fileSystemService.readDocument(
        session.document.path,
      );
      session.reloadFromDisk(diskDocument);
      showMessage('已载入磁盘版本', tone: AppMessageTone.success);
    } on FileSystemException catch (error) {
      showMessage(error.message, tone: AppMessageTone.error);
    }
  }

  void undoActiveDocument() {
    final session = activeSession;
    if (session == null) return;
    session.editorController.undo();
  }

  void redoActiveDocument() {
    final session = activeSession;
    if (session == null) return;
    session.editorController.redo();
  }

  Future<void> search(String query, SearchOptions options) async {
    final workspace = activeWorkspace;
    if (workspace == null || query.isEmpty) return;
    _searching = true;
    _searchError = null;
    notifyListeners();
    try {
      _searchReport = await _searchService.search(
        [workspace.path],
        query,
        options: options,
      );
    } on ArgumentError catch (error) {
      _searchError = error.message?.toString() ?? '搜索条件无效';
    } catch (error) {
      _searchError = error.toString();
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<ReplaceReport?> replaceAll(
    String query,
    String replacement,
    SearchOptions options,
  ) async {
    final workspace = activeWorkspace;
    if (workspace == null || query.isEmpty) return null;
    _searching = true;
    _searchError = null;
    notifyListeners();
    try {
      final saved = await _saveDirtyDocuments(workspace);
      if (!saved) return null;
      final report = await _searchService.replaceAll(
        [workspace.path],
        query,
        replacement,
        options: options,
      );
      await _reloadWorkspaceDocuments(workspace);
      await search(query, options);
      showMessage(
        '已替换 ${report.replacementCount} 处，涉及 ${report.changedFileCount} 个文件',
        tone: report.errors.isEmpty
            ? AppMessageTone.success
            : AppMessageTone.warning,
      );
      return report;
    } catch (error) {
      _searchError = error.toString();
      return null;
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<bool> _saveDirtyDocuments(WorkspaceItem workspace) async {
    for (final path in _workspaceDocuments[workspace.id] ?? const []) {
      final session = _sessions[path];
      if (session?.document.isDirty != true) continue;
      try {
        final saved = await _fileSystemService.saveDocument(session!.document);
        session.adoptSavedDocument(saved);
      } on ExternalFileChangeException {
        session!.markExternalChange();
        _searchError = '${session.document.name} 在磁盘上已变化';
        return false;
      }
    }
    return true;
  }

  Future<void> _reloadWorkspaceDocuments(WorkspaceItem workspace) async {
    for (final path in _workspaceDocuments[workspace.id] ?? const []) {
      final session = _sessions[path];
      if (session == null || !File(path).existsSync()) continue;
      final document = await _fileSystemService.readDocument(path);
      session.reloadFromDisk(document);
    }
  }

  Future<void> openSearchResult(SearchResult result) async {
    await openDocument(result.filePath);
    final session = _sessions[_normalize(result.filePath)];
    if (session == null) return;
    if ((session.document.isMarkdown || session.document.isHtml) &&
        session.viewMode == MarkdownViewMode.preview) {
      session.setViewMode(MarkdownViewMode.edit);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      session.jumpTo(result.lineNumber, result.columnNumber);
    });
  }

  void jumpToHeading(int lineNumber, String anchor) {
    final session = activeSession;
    if (session == null) return;
    _activeHeadingAnchor = anchor;
    if (session.viewMode != MarkdownViewMode.edit) {
      session.requestPreviewJump(anchor);
      return;
    }
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      session.jumpTo(lineNumber, 1);
    });
  }

  void openCurrentFileFind() {
    final session = activeSession;
    if (session == null) return;
    if (session.document.isMarkdown &&
        session.viewMode != MarkdownViewMode.edit) {
      session.previewFindController.open();
      return;
    }
    if (session.document.isHtml &&
        session.viewMode == MarkdownViewMode.preview) {
      session.setViewMode(MarkdownViewMode.edit);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      session.findController.findMode();
    });
  }

  void closeCurrentFileFind() {
    final session = activeSession;
    if (session == null) return;
    if (session.document.isMarkdown &&
        session.viewMode != MarkdownViewMode.edit) {
      session.previewFindController.close();
      return;
    }
    session.findController.close();
  }

  Future<void> openActiveHtmlInChrome() async {
    final session = activeSession;
    if (session == null || !session.document.isHtml) return;
    final path = session.document.path;
    if (!await File(path).exists()) {
      showMessage('文件不存在，无法在 Chrome 中打开', tone: AppMessageTone.error);
      return;
    }

    try {
      ProcessResult result;
      if (Platform.isMacOS) {
        result = await Process.run('open', ['-a', 'Google Chrome', path]);
        if (result.exitCode == 0) {
          showMessage('已在 Chrome 中打开', tone: AppMessageTone.success);
          return;
        }
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        result = await Process.run('cmd', [
          '/c',
          'start',
          '',
          'chrome',
          path,
        ], runInShell: true);
        if (result.exitCode == 0) {
          showMessage('已在 Chrome 中打开', tone: AppMessageTone.success);
          return;
        }
        await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
      } else {
        result = await Process.run('google-chrome', [path]);
        if (result.exitCode == 0) {
          showMessage('已在 Chrome 中打开', tone: AppMessageTone.success);
          return;
        }
        await Process.run('xdg-open', [path]);
      }
      showMessage('未找到 Chrome，已使用系统浏览器打开', tone: AppMessageTone.warning);
    } on ProcessException {
      showMessage('无法启动浏览器', tone: AppMessageTone.error);
    }
  }

  void showMessage(
    String message, {
    AppMessageTone tone = AppMessageTone.neutral,
  }) {
    _messageTimer?.cancel();
    _message = message;
    _messageTone = tone;
    notifyListeners();
    _messageTimer = Timer(const Duration(seconds: 4), () {
      _message = null;
      notifyListeners();
    });
  }

  Future<void> _onFileChanged(FileChangeEvent event) async {
    final session = _sessions[_normalize(event.path)];
    if (session != null) {
      if (event.type == FileChangeType.removed) {
        session.markDeleted();
      } else {
        try {
          final diskDocument = await _fileSystemService.readDocument(
            event.path,
          );
          if (diskDocument.content != session.document.savedContent) {
            if (session.document.isDirty) {
              session.markExternalChange();
              showMessage(
                '${session.document.name} 在磁盘上已更新',
                tone: AppMessageTone.warning,
              );
            } else {
              session.reloadFromDisk(diskDocument);
              showMessage(
                '已同步 ${session.document.name}',
                tone: AppMessageTone.neutral,
              );
            }
          } else if (!session.document.isDirty) {
            session.adoptSavedDocument(diskDocument);
          }
        } catch (_) {}
      }
    }

    final parent = p.dirname(_normalize(event.path));
    if (_directoryChildren.containsKey(parent) &&
        Directory(parent).existsSync()) {
      try {
        await _loadDirectory(parent);
      } catch (_) {}
    }
  }

  Future<void> _retainWatch(String path) async {
    final normalizedPath = _normalize(path);
    final count = _watchReferences[normalizedPath] ?? 0;
    _watchReferences[normalizedPath] = count + 1;
    if (count == 0) await _watchService.watchPath(normalizedPath);
  }

  Future<void> _releaseWatch(String path) async {
    final normalizedPath = _normalize(path);
    final count = _watchReferences[normalizedPath] ?? 0;
    if (count <= 1) {
      _watchReferences.remove(normalizedPath);
      await _watchService.unwatchPath(normalizedPath);
    } else {
      _watchReferences[normalizedPath] = count - 1;
    }
  }

  void _syncSidebarDefaults() {
    final workspace = activeWorkspace;
    if (workspace?.isFile == true && _explorerView == ExplorerView.files) {
      _leftCollapsed = true;
    } else if (workspace?.isDirectory == true) {
      _leftCollapsed = false;
      _explorerView = ExplorerView.files;
    }
    if (activeSession?.document.isMarkdown != true) _rightCollapsed = true;
  }

  /// Wires a freshly constructed session into the controller's listener
  /// graph so content edits propagate to sibling panes showing the same
  /// document and the UI rebuilds.
  EditorSession _createSession(DocumentModel document) {
    final session = EditorSession(document);
    session.addListener(() {
      _syncSessionContent(session);
      notifyListeners();
    });
    return session;
  }

  /// Pushes [source]'s content to every other live session that points at
  /// the same path. Used to keep split panes of one document in sync without
  /// sharing a single `CodeLineEditingController`.
  void _syncSessionContent(EditorSession source) {
    final sourcePath = source.document.path;
    for (final other in {..._sessions.values, ..._paneSessions.values}) {
      if (identical(other, source)) continue;
      if (other.document.path != sourcePath) continue;
      other.setExternalContent(source.document.content);
    }
  }

  String _generatePaneId() {
    return 'pane_${DateTime.now().microsecondsSinceEpoch}_'
        '${math.Random().nextInt(1 << 32).toRadixString(36)}';
  }

  /// Returns the split tree for the active workspace, or null when the
  /// workspace is in single-pane mode.
  SplitNode? get activeSplit => activeWorkspace?.split;

  /// True when the active workspace has more than one pane.
  bool get isSplit {
    final node = activeWorkspace?.split;
    return node != null && node.leaves.length > 1;
  }

  /// Returns the session backing [paneId]. Prefers a dedicated clone (each
  /// pane gets an independent controller so cursors don't fight); falls back
  /// to the primary session keyed by file path for the primary-most leaf,
  /// which intentionally shares the tab strip's canonical session to preserve
  /// cursor/scroll on the first split.
  EditorSession? paneSessionFor(String paneId) {
    // Always derive the pane's session from its active path. Per-pane clones
    // were abandoned because they didn't follow tab switches within a pane
    // (the clone was bound to whichever document the pane showed at split
    // time). Sharing the primary session means multi-pane edits of the same
    // file stay in sync automatically — cursor/scroll also sync, which is
    // an acceptable tradeoff (matches Sublime rather than VSCode).
    final leaf = paneLeaf(paneId);
    if (leaf == null) return activeSession;
    return _sessions[leaf.filePath];
  }

  /// Returns the SplitLeaf (with its openPaths / activeIndex) backing [paneId]
  /// in the active workspace. When the workspace isn't split, falls back to a
  /// synthesized leaf for the implicit 'root' pane whose openPaths mirror the
  /// workspace's open documents — so the UI can render a per-pane tab strip
  /// uniformly whether split or not.
  SplitLeaf? paneLeaf(String paneId) {
    final workspace = activeWorkspace;
    if (workspace == null) return null;
    final tree = workspace.split;
    if (tree != null) {
      for (final leaf in tree.leaves) {
        if (leaf.paneId == paneId) return leaf;
      }
      return null;
    }
    // Non-split fallback: only the implicit 'root' pane exists.
    if (paneId != 'root') return null;
    final docs = _workspaceDocuments[workspace.id];
    if (docs == null || docs.isEmpty) return null;
    final selected = workspace.selectedFilePath;
    final activeIndex = selected == null
        ? 0
        : docs.indexOf(selected).clamp(0, docs.length - 1);
    return SplitLeaf(
      paneId: 'root',
      openPaths: List<String>.from(docs),
      activeIndex: activeIndex,
    );
  }

  /// Splits the pane identified by [targetPaneId] along [axis], placing
  /// [filePath] in the new pane. The target pane keeps its existing session
  /// (cursor preserved); only the new pane gets a fresh clone.
  ///
  /// When [newPaneIsSecondary] is true (default), the new pane lands on the
  /// trailing side (right / bottom). When false, the new pane becomes the
  /// branch's primary (left / top) and the original pane is demoted to the
  /// secondary slot — used for drops on the leading edge of a pane.
  Future<void> splitPane({
    required String targetPaneId,
    required SplitAxis axis,
    required String filePath,
    bool newPaneIsSecondary = true,
  }) async {
    final workspace = activeWorkspace;
    if (workspace == null) return;

    // Treat the no-split case as an implicit leaf with targetPaneId so the
    // renderer can use a stable paneId ('root') without the controller
    // needing to assign one until a split actually happens.
    SplitNode current;
    SplitLeaf targetLeaf;
    if (workspace.split != null) {
      current = workspace.split!;
      if (!current.containsPane(targetPaneId)) return;
      targetLeaf = current.leaves.firstWhere(
        (leaf) => leaf.paneId == targetPaneId,
        orElse: () => SplitLeaf(paneId: targetPaneId, openPaths: const []),
      );
    } else {
      // First split: inherit ALL the workspace's open tabs (not just the
      // currently selected one) so the originating pane keeps every file the
      // user had open at the top, with the selected file as the active tab.
      final docs = List<String>.from(
        _workspaceDocuments[workspace.id] ?? const [],
      );
      if (docs.isEmpty) {
        final selected = workspace.selectedFilePath;
        if (selected == null) return;
        docs.add(selected);
      }
      final selected = workspace.selectedFilePath;
      final activeIndex = selected == null
          ? docs.length - 1
          : docs.indexOf(selected).clamp(0, docs.length - 1);
      targetLeaf = SplitLeaf(
        paneId: targetPaneId,
        openPaths: docs,
        activeIndex: activeIndex,
      );
      current = targetLeaf;
    }
    if (targetLeaf.openPaths.isEmpty) return;

    final primaryPath = targetLeaf.filePath;
    final newPaneId = _generatePaneId();
    final newPath = _normalize(filePath);

    // Ensure primary sessions exist for both files (tab strip, save, watch).
    await _ensurePrimarySession(primaryPath);
    await _ensurePrimarySession(newPath);
    // Clone only the new pane — target pane keeps its existing session.
    await _ensurePaneClone(newPaneId, newPath);

    final newLeaf = SplitLeaf(paneId: newPaneId, openPaths: [newPath]);
    final branch = newPaneIsSecondary
        ? SplitBranch(
            axis: axis,
            primary: targetLeaf,
            secondary: newLeaf,
            ratio: 0.5,
          )
        : SplitBranch(
            axis: axis,
            primary: newLeaf,
            secondary: targetLeaf,
            ratio: 0.5,
          );
    final next = workspace.split == null
        ? branch
        : current.replacePane(targetPaneId, branch) ?? branch;

    _replaceWorkspaceSplit(workspace, next);
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Opens [filePath] in [paneId] — pushing a new tab if the file isn't
  /// already open in this pane, or just activating the existing tab if it is.
  /// Used when a file is dropped into the center of a pane, or when an
  /// open/select call routes through a pane in split mode.
  Future<void> addToPaneDocument(String paneId, String filePath) async {
    final workspace = activeWorkspace;
    if (workspace == null || workspace.split == null) return;
    final current = workspace.split!;
    if (!current.containsPane(paneId)) return;

    final normalized = _normalize(filePath);
    await _ensurePrimarySession(normalized);

    // Make sure this pane has a backing clone session for the path so the
    // editor surface renders the right content even on non-primary panes.
    if (!_paneSessions.containsKey(paneId)) {
      await _ensurePaneClone(paneId, normalized);
    }

    final next = _addOrActivateInPane(current, paneId, normalized);
    if (identical(next, current)) {
      notifyListeners();
      return;
    }
    _replaceWorkspaceSplit(workspace, next);

    // Update workspace.selectedFilePath so sidebar / outline / sync follow.
    final leaf = next.leaves.firstWhere((l) => l.paneId == paneId);
    final index = _workspaces.indexOf(workspace);
    if (index >= 0) {
      _workspaces[index] = workspace.copyWith(
        selectedFilePath: leaf.filePath,
        split: next,
      );
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Legacy alias kept for callers (e.g. drop-zone center drop) that semantically
  /// mean "open this file in this pane" — now always pushes/activates a tab
  /// rather than replacing the pane's only document.
  Future<void> replacePaneDocument(String paneId, String filePath) =>
      addToPaneDocument(paneId, filePath);

  /// Removes the leaf [paneId] from the active workspace's split tree and
  /// promotes its sibling subtree in place of the parent branch. Disposes the
  /// clone that backed the removed leaf.
  void unsplitPane(String paneId) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final current = workspace.split;
    if (current == null) return;
    if (!current.containsPane(paneId)) return;
    final collapsed = current.collapseLeaf(paneId);
    final removedPath = _leafPath(current, paneId);
    _paneSessions.remove(paneId)?.dispose();
    if (removedPath != null) _maybeDisposePrimary(removedPath, tree: collapsed);
    _replaceWorkspaceSplit(workspace, collapsed);
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Tears down the entire split tree for the active workspace, disposing all
  /// pane clones and any primary sessions that no longer have a tab strip
  /// reference.
  void unsplitAll() {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final split = workspace.split;
    if (split == null) return;
    final paths = <String>{};
    for (final leaf in split.leaves) {
      paths.add(leaf.filePath);
    }
    for (final paneId in _paneSessions.keys.toList()) {
      _paneSessions.remove(paneId)?.dispose();
    }
    for (final path in paths) {
      _maybeDisposePrimary(path, tree: null);
    }
    final index = _workspaces.indexOf(workspace);
    if (index >= 0) {
      _workspaces[index] = workspace.copyWith(clearSplit: true);
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Nudges the split ratio of the branch containing [paneId] by [delta].
  void adjustSplitRatio(String paneId, double delta) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final split = workspace.split;
    if (split == null) return;
    final parent = split.findParentBranch(paneId);
    if (parent == null) return;
    final next = (parent.ratio + delta).clamp(0.1, 0.9).toDouble();
    if ((next - parent.ratio).abs() < 0.0001) return;
    _replaceWorkspaceSplit(workspace, _updateBranchRatio(split, paneId, next));
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Sets the split ratio of the branch containing [paneId]. Ratios that
  /// collapse past the edge auto-unsplit the smaller side.
  void setSplitRatio(String paneId, double ratio) {
    if (ratio < 0.15) {
      unsplitPane(_siblingPaneIdOf(paneId));
      return;
    }
    if (ratio > 0.85) {
      unsplitPane(paneId);
      return;
    }
    final clamped = ratio.clamp(0.1, 0.9).toDouble();
    final workspace = activeWorkspace;
    if (workspace == null) return;
    final split = workspace.split;
    if (split == null) return;
    final parent = split.findParentBranch(paneId);
    if (parent == null) return;
    if ((parent.ratio - clamped).abs() < 0.0001) return;
    _replaceWorkspaceSplit(
      workspace,
      _updateBranchRatio(split, paneId, clamped),
    );
    notifyListeners();
    _scheduleSessionSave();
  }

  SplitNode _updateBranchRatio(SplitNode node, String paneId, double ratio) {
    if (node is! SplitBranch) return node;
    if (node.primary.containsPane(paneId)) {
      final updated = _updateBranchRatio(node.primary, paneId, ratio);
      return SplitBranch(
        axis: node.axis,
        primary: updated,
        secondary: node.secondary,
        ratio: ratio,
      );
    }
    if (node.secondary.containsPane(paneId)) {
      final updated = _updateBranchRatio(node.secondary, paneId, ratio);
      return SplitBranch(
        axis: node.axis,
        primary: node.primary,
        secondary: updated,
        ratio: 1.0 - ratio,
      );
    }
    return node;
  }

  String _siblingPaneIdOf(String paneId) {
    final parent = activeWorkspace?.split?.findParentBranch(paneId);
    if (parent == null) return paneId;
    if (parent.primary.containsPane(paneId)) {
      return parent.secondary.leaves.first.paneId;
    }
    return parent.primary.leaves.first.paneId;
  }

  String? _leafPath(SplitNode node, String paneId) {
    for (final leaf in node.leaves) {
      if (leaf.paneId == paneId) return leaf.filePath;
    }
    return null;
  }

  /// Returns a copy of [node] with [path] added to (or activated within) the
  /// leaf identified by [paneId]. Returns the original node if no change was
  /// needed (e.g. [path] is already the active tab in that pane).
  SplitNode _addOrActivateInPane(SplitNode node, String paneId, String path) {
    if (node is SplitLeaf) {
      if (node.paneId != paneId) return node;
      final existing = node.openPaths.indexOf(path);
      if (existing >= 0) {
        if (existing == node.activeIndex) return node;
        return node.copyWith(activeIndex: existing);
      }
      final newPaths = [...node.openPaths, path];
      return node.copyWith(
        openPaths: newPaths,
        activeIndex: newPaths.length - 1,
      );
    }
    if (node is SplitBranch) {
      if (node.primary.containsPane(paneId)) {
        final updated = _addOrActivateInPane(node.primary, paneId, path);
        if (!identical(updated, node.primary)) {
          return SplitBranch(
            axis: node.axis,
            primary: updated,
            secondary: node.secondary,
            ratio: node.ratio,
          );
        }
      }
      if (node.secondary.containsPane(paneId)) {
        final updated = _addOrActivateInPane(node.secondary, paneId, path);
        if (!identical(updated, node.secondary)) {
          return SplitBranch(
            axis: node.axis,
            primary: node.primary,
            secondary: updated,
            ratio: node.ratio,
          );
        }
      }
    }
    return node;
  }

  /// Returns a copy of [node] with [paneId]'s activeIndex set to the position
  /// of [path], or null if no change was needed.
  SplitNode? _setActiveInPane(SplitNode node, String paneId, String path) {
    if (node is SplitLeaf) {
      if (node.paneId != paneId) return null;
      final i = node.openPaths.indexOf(path);
      if (i < 0 || i == node.activeIndex) return null;
      return node.copyWith(activeIndex: i);
    }
    if (node is SplitBranch) {
      final newPrimary = _setActiveInPane(node.primary, paneId, path);
      if (newPrimary != null) {
        return SplitBranch(
          axis: node.axis,
          primary: newPrimary,
          secondary: node.secondary,
          ratio: node.ratio,
        );
      }
      final newSecondary = _setActiveInPane(node.secondary, paneId, path);
      if (newSecondary != null) {
        return SplitBranch(
          axis: node.axis,
          primary: node.primary,
          secondary: newSecondary,
          ratio: node.ratio,
        );
      }
    }
    return null;
  }

  /// Returns a copy of [node] with [path] removed from [paneId]'s openPaths.
  /// Returns null if the pane doesn't contain [path]. If the resulting leaf
  /// would be empty, the caller should unsplit instead.
  SplitNode? _removePathFromPane(SplitNode node, String paneId, String path) {
    if (node is SplitLeaf) {
      if (node.paneId != paneId) return null;
      final removedAt = node.openPaths.indexOf(path);
      if (removedAt < 0) return null;
      final newPaths = [...node.openPaths]..removeAt(removedAt);
      var newActive = node.activeIndex;
      if (removedAt == node.activeIndex) {
        newActive = (removedAt - 1).clamp(0, newPaths.length - 1);
      } else if (removedAt < node.activeIndex) {
        newActive = node.activeIndex - 1;
      }
      return node.copyWith(openPaths: newPaths, activeIndex: newActive);
    }
    if (node is SplitBranch) {
      final newPrimary = _removePathFromPane(node.primary, paneId, path);
      if (newPrimary != null) {
        return SplitBranch(
          axis: node.axis,
          primary: newPrimary,
          secondary: node.secondary,
          ratio: node.ratio,
        );
      }
      final newSecondary = _removePathFromPane(node.secondary, paneId, path);
      if (newSecondary != null) {
        return SplitBranch(
          axis: node.axis,
          primary: node.primary,
          secondary: newSecondary,
          ratio: node.ratio,
        );
      }
    }
    return null;
  }

  /// Switches [paneId]'s active tab to [path]. No-op if the path isn't open in
  /// this pane. Updates workspace.selectedFilePath so sidebar/outline follow.
  /// In non-split mode, routes through [selectDocument] for compatibility.
  void selectPaneTab(String paneId, String path) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    if (workspace.split == null) {
      selectDocument(path);
      return;
    }
    final normalized = _normalize(path);
    final updated = _setActiveInPane(workspace.split!, paneId, normalized);
    if (updated == null) return;
    final leaf = updated.leaves.firstWhere((l) => l.paneId == paneId);
    final index = _workspaces.indexOf(workspace);
    if (index >= 0) {
      _workspaces[index] = workspace.copyWith(
        selectedFilePath: leaf.filePath,
        split: updated,
      );
    } else {
      _replaceWorkspaceSplit(workspace, updated);
    }
    _activeHeadingAnchor = null;
    _gitActiveDiff = null;
    notifyListeners();
    _scheduleSessionSave();
    unawaited(revealPathInWorkspace(normalized));
  }

  /// Closes [path] within [paneId]. If the pane becomes empty, unsplits it.
  /// Disposes the underlying session if no pane still references [path].
  /// In non-split mode, routes through [closeDocument] for compatibility.
  /// When [force] is false and the underlying session is dirty AND would be
  /// disposed (no other pane references it), the close is a no-op — callers
  /// should confirm with the user first.
  void closePaneTab(String paneId, String path, {bool force = false}) {
    final workspace = activeWorkspace;
    if (workspace == null) return;
    if (workspace.split == null) {
      closeDocument(path, force: force);
      return;
    }
    final current = workspace.split!;
    final leaf = current.leaves.firstWhere(
      (l) => l.paneId == paneId,
      orElse: () => SplitLeaf(paneId: paneId, openPaths: const []),
    );
    if (!leaf.openPaths.contains(path)) return;
    final normalized = _normalize(path);

    if (leaf.openPaths.length == 1) {
      // Pane becomes empty — unsplit it (handles session cleanup).
      if (!force) {
        final session = _sessions[normalized];
        final stillReferenced = current.leaves.any(
          (l) => l.paneId != paneId && l.openPaths.contains(normalized),
        );
        if (session?.document.isDirty == true && !stillReferenced) return;
      }
      unsplitPane(paneId);
      return;
    }

    final updated = _removePathFromPane(current, paneId, normalized);
    if (updated == null) return;
    if (!force) {
      final session = _sessions[normalized];
      final stillReferenced = updated.leaves.any(
        (l) => l.openPaths.contains(normalized),
      );
      if (session?.document.isDirty == true && !stillReferenced) return;
    }
    _maybeDisposePrimary(normalized, tree: updated);

    final newActivePath = updated.leaves
        .firstWhere((l) => l.paneId == paneId)
        .filePath;
    final index = _workspaces.indexOf(workspace);
    if (index >= 0) {
      _workspaces[index] = workspace.copyWith(
        selectedFilePath: newActivePath,
        split: updated,
      );
    } else {
      _replaceWorkspaceSplit(workspace, updated);
    }
    notifyListeners();
    _scheduleSessionSave();
  }

  /// Ensures a primary session exists for [filePath] (used by tab strip /
  /// save / file-watch). Silently skips on binary / oversized / missing files.
  Future<void> _ensurePrimarySession(String filePath) async {
    final normalized = _normalize(filePath);
    if (_sessions.containsKey(normalized)) return;
    try {
      final document = await _fileSystemService.readDocument(normalized);
      _sessions[normalized] = _createSession(document);
    } on BinaryFileException {
      return;
    } on FileTooLargeException {
      return;
    } on FileSystemException {
      return;
    }
  }

  /// Legacy clone-session factory. Per-pane clones were retired in favor of
  /// sharing the primary session — every pane now reads `_sessions[leaf.filePath]`
  /// directly via [paneSessionFor]. Kept as a no-op so callers (splitPane,
  /// addToPaneDocument, _restoreSplitTree) don't need updating.
  Future<void> _ensurePaneClone(String paneId, String filePath) async {}

  /// Drops the primary session for [path] when no pane in [tree] (defaults to
  /// the active workspace's current tree) and no workspace tab still needs it.
  void _maybeDisposePrimary(String path, {SplitNode? tree}) {
    final normalized = _normalize(path);
    final treeToCheck = tree ?? activeWorkspace?.split;
    final stillInTree =
        treeToCheck?.leaves.any(
          (leaf) => leaf.openPaths.contains(normalized),
        ) ??
        false;
    if (stillInTree) return;
    final stillTabbed = _workspaces.any(
      (ws) =>
          (ws.split == null && ws.selectedFilePath == normalized) ||
          (_workspaceDocuments[ws.id] ?? const []).contains(normalized),
    );
    if (stillTabbed) return;
    _sessions.remove(normalized)?.dispose();
  }

  void _replaceWorkspaceSplit(WorkspaceItem workspace, SplitNode? next) {
    final index = _workspaces.indexOf(workspace);
    if (index < 0) return;
    _workspaces[index] = next == null
        ? workspace.copyWith(clearSplit: true)
        : workspace.copyWith(split: next);
  }

  /// Propagates terminal layout changes and persists dock preferences.
  void _onTerminalWorkspaceChanged() {
    notifyListeners();
    _scheduleSessionSave();
  }

  Future<void> _restoreWorkspace(Map<String, dynamic> value) async {
    final path = value['path'];
    final typeName = value['type'];
    if (path is! String || typeName is! String) return;
    final type = typeName == WorkspaceItemType.directory.name
        ? WorkspaceItemType.directory
        : WorkspaceItemType.file;
    final normalizedPath = _normalize(path);
    final entityType = await FileSystemEntity.type(
      normalizedPath,
      followLinks: false,
    );
    if ((type == WorkspaceItemType.directory &&
            entityType != FileSystemEntityType.directory) ||
        (type == WorkspaceItemType.file &&
            entityType != FileSystemEntityType.file)) {
      return;
    }

    var workspace = WorkspaceItem(
      path: normalizedPath,
      name: p.basename(normalizedPath),
      type: type,
    );
    _workspaces.add(workspace);
    _workspaceDocuments[workspace.id] = [];
    await _retainWatch(workspace.path);
    if (workspace.isDirectory) {
      await _loadDirectory(workspace.path, expand: true);
    }

    final savedDocuments = value['documents'];
    final paths = savedDocuments is List
        ? savedDocuments.whereType<String>()
        : <String>[workspace.path];
    for (final documentPath in paths) {
      await _restoreDocument(workspace, documentPath);
    }

    final documents = _workspaceDocuments[workspace.id] ?? const <String>[];
    final selectedPath = value['selectedFilePath'];
    final selected = selectedPath is String && documents.contains(selectedPath)
        ? selectedPath
        : documents.isEmpty
        ? null
        : documents.first;
    workspace = workspace.copyWith(
      selectedFilePath: selected,
      clearSelectedFilePath: selected == null,
    );
    _workspaces[_workspaces.length - 1] = workspace;

    final splitValue = value['split'];
    if (splitValue is Map<String, dynamic>) {
      try {
        final split = SplitNode.fromJson(splitValue);
        await _restoreSplitTree(workspace, split);
        final index = _workspaces.indexOf(workspace);
        if (index >= 0) {
          _workspaces[index] = workspace.copyWith(split: split);
        }
      } on FormatException {
        // Stale / malformed split JSON — drop it and use the single-doc view.
      }
    }
  }

  Future<void> _restoreSplitTree(
    WorkspaceItem workspace,
    SplitNode node,
  ) async {
    final leaves = node.leaves;
    for (var i = 0; i < leaves.length; i++) {
      final leaf = leaves[i];
      // Ensure a session exists for every tab in this pane (not just the
      // active one) so the user can switch tabs without re-reading the file.
      for (final rawPath in leaf.openPaths) {
        final normalized = _normalize(rawPath);
        try {
          await _ensurePrimarySession(normalized);
        } on FileSystemException {
          continue;
        }
        final documents = _workspaceDocuments[workspace.id] ??= [];
        if (!documents.contains(normalized)) documents.add(normalized);
      }
      // Primary-most leaf (i == 0) reuses the primary session for its active
      // document; every other leaf gets its own clone so cursors stay
      // independent.
      if (i > 0) {
        await _ensurePaneClone(leaf.paneId, _normalize(leaf.filePath));
      }
    }
  }

  Future<void> _restoreDocument(WorkspaceItem workspace, String path) async {
    final normalizedPath = _normalize(path);
    if (await FileSystemEntity.type(normalizedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    try {
      final session =
          _sessions[normalizedPath] ??
          _createSession(await _fileSystemService.readDocument(normalizedPath));
      _sessions[normalizedPath] = session;
      final documents = _workspaceDocuments[workspace.id] ??= [];
      if (!documents.contains(normalizedPath)) documents.add(normalizedPath);
    } on BinaryFileException {
      return;
    } on FileTooLargeException {
      return;
    } on FileSystemException {
      return;
    }
  }

  void _restoreRecentItems(Object? value) {
    if (value is! List) return;
    for (final entry in value) {
      if (entry is! Map) continue;
      final path = entry['path'];
      final typeName = entry['type'];
      if (path is! String || typeName is! String || path.isEmpty) continue;
      final type = typeName == WorkspaceItemType.directory.name
          ? WorkspaceItemType.directory
          : WorkspaceItemType.file;
      final item = WorkspaceItem(
        path: _normalize(path),
        name: p.basename(path),
        type: type,
      );
      if (_recentItems.any((recent) => recent.id == item.id)) continue;
      _recentItems.add(item);
      if (_recentItems.length == 10) break;
    }
  }

  void _recordRecent(WorkspaceItem item) {
    final normalized = WorkspaceItem(
      path: _normalize(item.path),
      name: p.basename(item.path),
      type: item.type,
    );
    _recentItems.removeWhere((recent) => recent.id == normalized.id);
    _recentItems.insert(0, normalized);
    if (_recentItems.length > 10)
      _recentItems.removeRange(10, _recentItems.length);
  }

  void _scheduleSessionSave() {
    if (_restoringSession) return;
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_persistSession()),
    );
  }

  Future<void> _persistSession() {
    if (_restoringSession) return Future<void>.value();
    final snapshot = _sessionSnapshot();
    _sessionWriteQueue = _sessionWriteQueue
        .catchError((Object _) {})
        .then<void>((_) => _sessionStore.write(snapshot))
        .catchError((Object _) {});
    return _sessionWriteQueue;
  }

  Map<String, dynamic> _sessionSnapshot() {
    final workspaces = _workspaces
        .map(
          (workspace) => <String, dynamic>{
            'path': workspace.path,
            'type': workspace.type.name,
            'selectedFilePath': workspace.selectedFilePath,
            'documents': _workspaceDocuments[workspace.id] ?? const [],
            if (workspace.split != null) 'split': workspace.split!.toJson(),
          },
        )
        .toList(growable: false);
    return {
      'activeWorkspaceId': activeWorkspace?.id,
      'workspaces': workspaces,
      'recentItems': _recentItems
          .map(
            (item) => <String, dynamic>{
              'path': item.path,
              'type': item.type.name,
            },
          )
          .toList(growable: false),
      'leftCollapsed': _leftCollapsed,
      'rightCollapsed': _rightCollapsed,
      'leftSidebarWidth': _leftSidebarWidth,
      'rightSidebarWidth': _rightSidebarWidth,
      'explorerView': _explorerView.name,
      'themeId': _currentThemeId,
      'iconThemeId': _currentIconThemeId,
      'fontScale': _fontScale,
      'fileTreeHoverMode': _fileTreeHoverMode.name,
      'terminalDock': terminalWorkspace.dock.name,
      'terminalBottomExtent': terminalWorkspace.bottomExtent,
      'terminalRightExtent': terminalWorkspace.rightExtent,
    };
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on BinaryFileException {
      showMessage('暂不支持二进制文件', tone: AppMessageTone.warning);
    } on FileTooLargeException {
      showMessage('文件过大，超过 16 MB 安全限制', tone: AppMessageTone.warning);
    } on FileSystemException catch (error) {
      showMessage(error.message, tone: AppMessageTone.error);
    } catch (error) {
      showMessage(error.toString(), tone: AppMessageTone.error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _normalize(String path) => p.normalize(p.absolute(path));

  String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\\"'\\\"'")}'";

  String _appleScriptString(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  @override
  void dispose() {
    _messageTimer?.cancel();
    _sessionPersistTimer?.cancel();
    _watchSubscription.cancel();
    for (final session in _sessions.values) {
      session.dispose();
    }
    for (final session in _paneSessions.values) {
      session.dispose();
    }
    _watchService.dispose();
    terminalWorkspace.removeListener(_onTerminalWorkspaceChanged);
    terminalWorkspace.dispose();
    super.dispose();
  }
}
