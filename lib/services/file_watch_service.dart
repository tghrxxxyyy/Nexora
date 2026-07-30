import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart' as watcher;

import '../models/file_change_event.dart';

class FileWatchService {
  FileWatchService({this.debounceDuration = const Duration(milliseconds: 120)});

  final Duration debounceDuration;
  final StreamController<FileChangeEvent> _changeController =
      StreamController<FileChangeEvent>.broadcast();
  final Map<String, _WatchRegistration> _registrations =
      <String, _WatchRegistration>{};
  final Map<String, Timer> _debounceTimers = <String, Timer>{};
  final Map<String, FileChangeEvent> _pendingEvents =
      <String, FileChangeEvent>{};
  bool _disposed = false;

  Stream<FileChangeEvent> get changes => _changeController.stream;

  Set<String> get watchedPaths => Set<String>.unmodifiable(_registrations.keys);

  Future<void> watchPath(String targetPath) async {
    _ensureActive();
    final normalizedTarget = _normalize(targetPath);
    if (_registrations.containsKey(normalizedTarget)) {
      return;
    }

    final targetType = await FileSystemEntity.type(
      normalizedTarget,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Cannot watch a missing path',
        normalizedTarget,
      );
    }

    final watchesSingleFile = targetType != FileSystemEntityType.directory;
    final watcherPath = watchesSingleFile
        ? p.dirname(normalizedTarget)
        : normalizedTarget;
    final directoryWatcher = watcher.DirectoryWatcher(watcherPath);
    final subscription = directoryWatcher.events.listen((event) {
      final changedPath = _normalize(event.path);
      if (watchesSingleFile && changedPath != normalizedTarget) {
        return;
      }
      _schedule(
        FileChangeEvent(
          watchedPath: normalizedTarget,
          path: changedPath,
          type: _mapType(event.type),
          occurredAt: DateTime.now(),
        ),
      );
    }, onError: _changeController.addError);

    _registrations[normalizedTarget] = _WatchRegistration(
      subscription: subscription,
    );
    try {
      await directoryWatcher.ready;
    } catch (_) {
      await unwatchPath(normalizedTarget);
      rethrow;
    }
  }

  Future<void> watchPaths(Iterable<String> paths) async {
    for (final path in paths) {
      await watchPath(path);
    }
  }

  Future<void> unwatchPath(String targetPath) async {
    final normalizedTarget = _normalize(targetPath);
    final registration = _registrations.remove(normalizedTarget);
    await registration?.subscription.cancel();

    final pendingKeys = _pendingEvents.entries
        .where((entry) => entry.value.watchedPath == normalizedTarget)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in pendingKeys) {
      _debounceTimers.remove(key)?.cancel();
      _pendingEvents.remove(key);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pendingEvents.clear();
    final subscriptions = _registrations.values
        .map((registration) => registration.subscription)
        .toList(growable: false);
    _registrations.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _changeController.close();
  }

  void _schedule(FileChangeEvent event) {
    if (_disposed) {
      return;
    }
    final key = '${event.watchedPath}\u0000${event.path}';
    _pendingEvents[key] = event;
    _debounceTimers.remove(key)?.cancel();
    _debounceTimers[key] = Timer(debounceDuration, () {
      _debounceTimers.remove(key);
      final pendingEvent = _pendingEvents.remove(key);
      if (pendingEvent != null && !_changeController.isClosed) {
        _changeController.add(pendingEvent);
      }
    });
  }

  FileChangeType _mapType(watcher.ChangeType type) {
    if (type == watcher.ChangeType.ADD) {
      return FileChangeType.added;
    }
    if (type == watcher.ChangeType.REMOVE) {
      return FileChangeType.removed;
    }
    return FileChangeType.modified;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('FileWatchService has been disposed');
    }
  }

  String _normalize(String path) => p.normalize(p.absolute(path));
}

class _WatchRegistration {
  const _WatchRegistration({required this.subscription});

  final StreamSubscription<watcher.WatchEvent> subscription;
}
