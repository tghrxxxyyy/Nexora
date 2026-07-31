import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/file_change_event.dart';
import '../models/file_node.dart';
import '../models/search_models.dart';
import '../models/terminal_layout.dart';
import '../models/workspace_item.dart';
import '../services/file_picker_service.dart';
import '../services/app_session_store.dart';
import '../services/file_system_service.dart';
import '../services/file_watch_service.dart';
import '../services/global_search_service.dart';
import 'editor_session.dart';
import 'terminal_workspace_controller.dart';

enum ExplorerView { files, search }

enum AppMessageTone { neutral, success, warning, error }

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
  }

  final FilePickerService _pickerService;
  final FileSystemService _fileSystemService;
  final FileWatchService _watchService;
  final GlobalSearchService _searchService;
  final AppSessionStore _sessionStore;
  final TerminalWorkspaceController terminalWorkspace =
      TerminalWorkspaceController();
  late final StreamSubscription<FileChangeEvent> _watchSubscription;

  final List<WorkspaceItem> _workspaces = [];
  final List<WorkspaceItem> _recentItems = [];
  final Map<String, EditorSession> _sessions = {};
  final Map<String, List<String>> _workspaceDocuments = {};
  final Map<String, List<FileNode>> _directoryChildren = {};
  final Set<String> _expandedDirectories = {};
  final Set<String> _expandedFileHeadings = {};
  final Map<String, int> _watchReferences = {};
  int _activeWorkspaceIndex = -1;
  bool _leftCollapsed = false;
  bool _rightCollapsed = false;
  ExplorerView _explorerView = ExplorerView.files;
  bool _busy = false;
  bool _searching = false;
  bool _globalReplaceRequested = false;
  AppThemeMode _themeMode = AppThemeMode.light;
  double _fontScale = 1;
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

  List<WorkspaceItem> get workspaces => List.unmodifiable(_workspaces);
  List<WorkspaceItem> get recentItems => List.unmodifiable(_recentItems);
  Map<String, EditorSession> get sessions => Map.unmodifiable(_sessions);
  Set<String> get expandedDirectories => Set.unmodifiable(_expandedDirectories);
  Set<String> get expandedFileHeadings =>
      Set.unmodifiable(_expandedFileHeadings);
  int get activeWorkspaceIndex => _activeWorkspaceIndex;
  bool get leftCollapsed => _leftCollapsed;
  bool get rightCollapsed => _rightCollapsed;
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
  AppThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;
  String? get activeHeadingAnchor => _activeHeadingAnchor;
  SearchReport? get searchReport => _searchReport;
  String? get searchError => _searchError;
  String? get message => _message;
  AppMessageTone get messageTone => _messageTone;
  bool get hasDirtyDocuments =>
      _sessions.values.any((session) => session.document.isDirty);

  Future<void> restoreSession() async {
    if (_sessionRestored || _restoringSession) return;
    _restoringSession = true;
    try {
      final state = await _sessionStore.read();
      if (state == null) return;
      final workspaces = state['workspaces'];
      if (workspaces is! List) return;
      _leftCollapsed = state['leftCollapsed'] == true;
      _rightCollapsed = state['rightCollapsed'] == true;
      _explorerView = state['explorerView'] == ExplorerView.search.name
          ? ExplorerView.search
          : ExplorerView.files;
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
      _themeMode = AppThemeMode.light;
      _fontScale = state['fontScale'] is num
          ? (state['fontScale'] as num).toDouble().clamp(0.85, 1.45).toDouble()
          : 1;
      AppColors.use(_themeMode);
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
            _explorerView == ExplorerView.search);
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
    _syncSidebarDefaults();
    notifyListeners();
    _scheduleSessionSave();
  }

  Future<void> closeWorkspace(int index, {bool force = false}) async {
    if (index < 0 || index >= _workspaces.length) return;
    final workspace = _workspaces[index];
    if (!force && workspaceHasDirtyDocuments(workspace)) return;

    await _releaseWatch(workspace.path);
    final documentPaths = List<String>.from(
      _workspaceDocuments.remove(workspace.id) ?? const [],
    );
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

  Future<void> _openDocumentFor(WorkspaceItem workspace, String path) async {
    final normalizedPath = _normalize(path);
    var session = _sessions[normalizedPath];
    if (session == null) {
      final document = await _fileSystemService.readDocument(normalizedPath);
      session = EditorSession(document)..addListener(_onSessionChanged);
      _sessions[normalizedPath] = session;
    }

    final documents = _workspaceDocuments[workspace.id] ??= [];
    if (!documents.contains(normalizedPath)) documents.add(normalizedPath);
    final workspaceIndex = _workspaces.indexOf(workspace);
    if (workspaceIndex >= 0) {
      _workspaces[workspaceIndex] = workspace.copyWith(
        selectedFilePath: normalizedPath,
      );
    }
    _activeWorkspaceIndex = workspaceIndex;
    notifyListeners();
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
    _workspaces[_activeWorkspaceIndex] = workspace.copyWith(
      selectedFilePath: normalizedPath,
    );
    _recordRecent(
      WorkspaceItem(
        path: normalizedPath,
        name: p.basename(normalizedPath),
        type: WorkspaceItemType.file,
      ),
    );
    _activeHeadingAnchor = null;
    notifyListeners();
    _scheduleSessionSave();
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
        final session = EditorSession(document)..addListener(_onSessionChanged);
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

  void toggleTheme() {
    _themeMode = _themeMode == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    AppColors.use(_themeMode);
    notifyListeners();
    _scheduleSessionSave();
  }

  void setFontScale(double value) {
    final nextValue = value.clamp(0.85, 1.45).toDouble();
    if ((_fontScale - nextValue).abs() < 0.001) return;
    _fontScale = nextValue;
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

  void showFiles() {
    _explorerView = ExplorerView.files;
    if (activeWorkspace?.isDirectory == true) _leftCollapsed = false;
    notifyListeners();
    _scheduleSessionSave();
  }

  void showGlobalSearch() {
    _explorerView = ExplorerView.search;
    _leftCollapsed = false;
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

  void _onSessionChanged() {
    notifyListeners();
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
          (EditorSession(await _fileSystemService.readDocument(normalizedPath))
            ..addListener(_onSessionChanged));
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
      'explorerView': _explorerView.name,
      'themeMode': _themeMode.name,
      'fontScale': _fontScale,
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
    _watchService.dispose();
    terminalWorkspace.removeListener(_onTerminalWorkspaceChanged);
    terminalWorkspace.dispose();
    super.dispose();
  }
}
