import '../services/file_icon_resolver.dart';

/// A selectable icon theme: a stable id, display name, and the [resolver]
/// that turns a path into a [FileVisual].
class FileIconTheme {
  const FileIconTheme({
    required this.id,
    required this.name,
    required this.resolver,
  });

  final String id;
  final String name;
  final FileIconResolver resolver;
}

/// Owns the registry of selectable icon themes. Mirrors [ThemeRegistry]'s
/// shape (without the import/persist machinery — icon themes are built-in
/// only for now). Add new themes here in the constructor.
class IconThemeRegistry {
  IconThemeRegistry() {
    _themes.add(
      const FileIconTheme(
        id: _kMaterialIconThemeId,
        name: 'Material Icon Theme',
        resolver: MaterialIconThemeFileIconResolver(),
      ),
    );
    _themes.add(
      const FileIconTheme(
        id: _kMaterialFallbackId,
        name: 'Material（内置）',
        resolver: MaterialFileIconResolver(),
      ),
    );
  }

  static const String defaultId = _kMaterialIconThemeId;
  static const String _kMaterialIconThemeId = 'material-icon-theme';
  static const String _kMaterialFallbackId = 'material';

  final List<FileIconTheme> _themes = [];

  List<FileIconTheme> get themes => List.unmodifiable(_themes);

  FileIconTheme? find(String? id) {
    if (id == null) return null;
    for (final theme in _themes) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}
