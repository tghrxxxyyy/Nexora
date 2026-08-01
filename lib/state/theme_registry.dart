import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../services/theme_loader.dart';

export '../services/theme_loader.dart' show ThemeLoader, ThemeFormatException;

/// Owns the list of selectable themes: built-in presets plus any user-imported
/// JSON files persisted under `getApplicationSupportDirectory()/themes/`.
class ThemeRegistry {
  ThemeRegistry({this._loader = const ThemeLoader()}) {
    _themes = List.of(AppColors.builtinThemes);
  }

  final ThemeLoader _loader;
  late List<AppThemeDefinition> _themes;

  List<AppThemeDefinition> get themes => List.unmodifiable(_themes);
  List<AppThemeDefinition> get imported =>
      _themes.where((theme) => !theme.builtIn).toList(growable: false);

  AppThemeDefinition? find(String id) {
    for (final theme in _themes) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// Loads any imported themes from the user themes directory.
  ///
  /// Malformed files are silently skipped at startup; the import flow surfaces
  /// parse errors interactively via the picker.
  Future<void> loadImported() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'themes'));
    if (!dir.existsSync()) return;

    final files = dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => p.extension(file.path).toLowerCase() == '.json');

    for (final file in files) {
      try {
        final source = await file.readAsString();
        final theme = _loader.parse(
          source,
          fallbackId: p.basenameWithoutExtension(file.path),
        );
        if (find(theme.id) == null) {
          _themes.add(theme);
        }
      } on Exception {
        // Ignore unreadable files at startup.
      }
    }
  }

  /// Persists an imported theme to disk and registers it in memory.
  ///
  /// If a theme with the same id already exists, the id is suffixed with `-N`
  /// until unique so existing themes (built-in or imported) are never replaced.
  Future<AppThemeDefinition> addImported(AppThemeDefinition theme) async {
    var unique = theme;
    var counter = 1;
    while (find(unique.id) != null) {
      unique = theme.copyWith(id: '${theme.id}-$counter');
      counter++;
    }

    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'themes'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, '${unique.id}.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_loader.toJson(unique)));

    _themes.add(unique);
    return unique;
  }

  /// Removes an imported theme and deletes its backing file. Built-in themes
  /// cannot be removed (returns false). Returns true on success.
  Future<bool> remove(String id) async {
    final theme = find(id);
    if (theme == null || theme.builtIn) return false;

    _themes.removeWhere((entry) => entry.id == id);
    final support = await getApplicationSupportDirectory();
    final file = File(p.join(support.path, 'themes', '$id.json'));
    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException {
        // Best-effort; in-memory removal already succeeded.
      }
    }
    return true;
  }
}
