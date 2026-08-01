import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';

/// Information about the file or directory being visualized.
class FileIconContext {
  const FileIconContext({
    required this.path,
    required this.isDirectory,
    this.expanded = false,
    this.dirty = false,
  });

  /// Absolute path used for extension and basename matching (Dockerfile, .gitignore…).
  final String path;
  final bool isDirectory;
  final bool expanded;
  final bool dirty;
}

/// Resolution result. Exactly one of [icon] (Material) or [svgAssetKey]
  /// (Material Icon Theme SVG) is non-null. [color] is meaningful for the
  /// Material path; for SVG assets the icon's own colors are authoritative
  /// unless the resolver asks for a tinted one (folders).
  class FileVisual {
  const FileVisual({
    this.icon,
    this.svgAssetKey,
    this.color,
    this.label,
    this.tintSvg = false,
  });

  final IconData? icon;

  /// Asset key under assets/icons/file-types/ (without leading 'assets/').
  final String? svgAssetKey;

  /// Color for Material icon / badge text, or the tint applied to an SVG asset
  /// when [tintSvg] is true.
  final Color? color;

  /// Short badge label used by the Material fallback theme.
  final String? label;

  /// When true, the SVG asset should be tinted via a ColorFilter using [color].
  /// Used for folders so they can follow the active Nexora palette.
  final bool tintSvg;
}

/// Resolves a [FileIconContext] into a [FileVisual]. Implemented by each
/// registered icon theme (Material fallback, Material Icon Theme SVG…).
abstract class FileIconResolver {
  FileVisual resolve(FileIconContext ctx);
}

/// Currently active resolver used by the top-level [resolveFileVisual].
/// Set by [AppController] whenever the icon theme changes.
FileIconResolver _activeResolver = MaterialIconThemeFileIconResolver();

void setActiveFileIconResolver(FileIconResolver resolver) {
  _activeResolver = resolver;
}

/// Convenience entry point used by sidebar and tab widgets. Forwards to the
/// active resolver configured on [AppController].
FileVisual resolveFileVisual(FileIconContext ctx) {
  return _activeResolver.resolve(ctx);
}

/// Material Icon Theme (SVG) implementation. Folders are tinted at runtime so
/// they follow the active Nexora palette; file-type icons keep their original
/// baked-in colors (the colorful Material Icon Theme look).
class MaterialIconThemeFileIconResolver implements FileIconResolver {
  const MaterialIconThemeFileIconResolver();

  static const _assetRoot = 'assets/icons/file-types/';

  @override
  FileVisual resolve(FileIconContext ctx) {
    if (ctx.isDirectory) {
      return FileVisual(
        svgAssetKey: ctx.expanded
            ? '${_assetRoot}folder-open.svg'
            : '${_assetRoot}folder.svg',
        color: AppColors.amber,
        tintSvg: true,
      );
    }

    final basename = p.basename(ctx.path);
    final special = _specialNames[basename];
    if (special != null) {
      return FileVisual(svgAssetKey: '$_assetRoot$special.svg');
    }

    final ext = p.extension(ctx.path).toLowerCase();
    final mapped = _extensionMap[ext];
    if (mapped != null) {
      return FileVisual(svgAssetKey: '$_assetRoot$mapped.svg');
    }

    return const FileVisual(svgAssetKey: '${_assetRoot}file-default.svg');
  }

  /// Maps a file's extension (lower-cased, with leading dot) onto a base icon
  /// name. Multiple extensions can map to the same icon (e.g. .jpg/.jpeg →
  /// image). Names without a dedicated asset fall back to [file-default].
  static const _extensionMap = <String, String>{
    '.md': 'markdown',
    '.markdown': 'markdown',
    '.mdx': 'markdown',
    '.doc': 'word',
    '.docx': 'word',
    '.rtf': 'word',
    '.ppt': 'powerpoint',
    '.pptx': 'powerpoint',
    '.key': 'powerpoint',
    '.pdf': 'pdf',
    '.html': 'html',
    '.htm': 'html',
    '.xml': 'html',
    '.css': 'css',
    '.scss': 'sass',
    '.sass': 'sass',
    '.less': 'less',
    '.java': 'java',
    '.kt': 'kotlin',
    '.kts': 'kotlin',
    '.py': 'python',
    '.pyi': 'python',
    '.js': 'javascript',
    '.mjs': 'javascript',
    '.cjs': 'javascript',
    '.jsx': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.dart': 'dart',
    '.go': 'go',
    '.rs': 'rust',
    '.c': 'c',
    '.h': 'h',
    '.cpp': 'cpp',
    '.cc': 'cpp',
    '.cxx': 'cpp',
    '.hpp': 'cpp',
    '.cs': 'csharp',
    '.swift': 'swift',
    '.rb': 'ruby',
    '.php': 'php',
    '.ex': 'elixir',
    '.exs': 'elixir',
    '.erl': 'erlang',
    '.elm': 'elm',
    '.hs': 'haskell',
    '.hx': 'haxe',
    '.jl': 'julia',
    '.pl': 'perl',
    '.lua': 'lua',
    '.nim': 'nim',
    '.ml': 'ocaml',
    '.cr': 'crystal',
    '.groovy': 'groovy',
    '.gradle': 'gradle',
    '.clj': 'clojure',
    '.cljs': 'clojure',
    '.edn': 'clojure',
    '.as': 'actionscript',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.toml': 'toml',
    '.graphql': 'graphql',
    '.gql': 'graphql',
    '.proto': 'proto',
    '.sql': 'sql',
    '.ps1': 'powershell',
    '.psm1': 'powershell',
    '.bat': 'shell',
    '.cmd': 'shell',
    '.sh': 'bash',
    '.zsh': 'bash',
    '.bash': 'bash',
    '.fish': 'bash',
    '.vue': 'vue',
    '.svelte': 'svelte',
    '.astro': 'astro',
    '.png': 'image',
    '.jpg': 'image',
    '.jpeg': 'image',
    '.gif': 'image',
    '.webp': 'image',
    '.bmp': 'image',
    '.tiff': 'image',
    '.tif': 'image',
    '.svg': 'svg',
    '.ico': 'image',
    '.mp4': 'video',
    '.mov': 'video',
    '.avi': 'video',
    '.mkv': 'video',
    '.webm': 'video',
    '.flv': 'video',
    '.mp3': 'audio',
    '.wav': 'audio',
    '.m4a': 'audio',
    '.flac': 'audio',
    '.ogg': 'audio',
    '.aac': 'audio',
    '.zip': 'zip',
    '.rar': 'zip',
    '.7z': 'zip',
    '.tar': 'zip',
    '.gz': 'zip',
    '.bz2': 'zip',
    '.exe': 'exe',
    '.dll': 'dll',
    '.so': 'dll',
    '.dylib': 'dll',
    '.lock': 'lock',
  };

  /// Exact basename matches (case-sensitive) that take precedence over the
  /// extension table — Dockerfile, package.json, pubspec.yaml, etc.
  static const _specialNames = <String, String>{
    'Dockerfile': 'docker',
    'docker-compose.yml': 'docker',
    'docker-compose.yaml': 'docker',
    'Makefile': 'makefile',
    'makefile': 'makefile',
    'LICENSE': 'license',
    'LICENSE.md': 'license',
    'LICENSE.txt': 'license',
    'README.md': 'readme',
    'README': 'readme',
    'CHANGELOG.md': 'changelog',
    'CHANGELOG': 'changelog',
    'TODO.md': 'todo',
    'package.json': 'json',
    'package-lock.json': 'lock',
    'pubspec.yaml': 'dart',
    'pubspec.lock': 'lock',
    'tsconfig.json': 'tsconfig',
    'jsconfig.json': 'jsconfig',
    '.gitignore': 'git',
    '.gitattributes': 'git',
    '.gitlab-ci.yml': 'gitlab',
    '.editorconfig': 'editorconfig',
    '.env': 'lock',
    '.env.local': 'lock',
    '.eslintrc': 'eslint',
    '.eslintrc.json': 'eslint',
    '.eslintrc.js': 'eslint',
    '.prettierrc': 'prettier',
    'vite.config.js': 'vite',
    'vite.config.ts': 'vite',
    'webpack.config.js': 'webpack',
    'webpack.config.ts': 'webpack',
    'Brewfile': 'lock',
    'CMakeLists.txt': 'cmake',
    'Gemfile': 'gemfile',
    'Gemfile.lock': 'lock',
    'Rakefile': 'ruby',
  };
}

/// Original Material Icon fallback theme. Mirrors the inline `_visualFor`
/// table that used to live in `file_sidebar.dart` so users can opt out of SVG
/// assets entirely if a Material Icon Theme asset is missing.
class MaterialFileIconResolver implements FileIconResolver {
  const MaterialFileIconResolver();

  @override
  FileVisual resolve(FileIconContext ctx) {
    if (ctx.isDirectory) {
      return FileVisual(
        icon: ctx.expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        color: AppColors.amber,
      );
    }
    return switch (p.extension(ctx.path).toLowerCase()) {
      '.md' || '.markdown' => FileVisual(
        label: 'MD',
        color: AppColors.signal,
      ),
      '.doc' || '.docx' || '.rtf' => FileVisual(
        icon: Icons.description_rounded,
        color: const Color(0xFF5AA8FF),
      ),
      '.xls' || '.xlsx' || '.csv' => FileVisual(
        icon: Icons.table_chart_rounded,
        color: const Color(0xFF5BA7E7),
      ),
      '.ppt' || '.pptx' || '.key' => FileVisual(
        icon: Icons.slideshow_rounded,
        color: const Color(0xFFFF9D5C),
      ),
      '.pdf' => FileVisual(
        icon: Icons.picture_as_pdf_rounded,
        color: AppColors.coral,
      ),
      '.html' || '.htm' || '.xml' => FileVisual(
        icon: Icons.html_rounded,
        color: AppColors.coral,
      ),
      '.css' || '.scss' || '.less' => FileVisual(
        icon: Icons.style_rounded,
        color: const Color(0xFF8CB8FF),
      ),
      '.java' || '.kt' || '.kts' => FileVisual(
        icon: Icons.coffee_rounded,
        color: const Color(0xFFFFA86A),
      ),
      '.py' || '.pyi' => FileVisual(
        label: 'PY',
        color: const Color(0xFF7CB7FF),
      ),
      '.js' || '.jsx' => FileVisual(
        label: 'JS',
        color: const Color(0xFFF3CE4B),
      ),
      '.ts' || '.tsx' => FileVisual(
        label: 'TS',
        color: const Color(0xFF4C9CFF),
      ),
      '.dart' => FileVisual(label: 'DART', color: const Color(0xFF55C4E7)),
      '.sql' => FileVisual(label: 'SQL', color: const Color(0xFFFFA86A)),
      '.json' ||
      '.yaml' ||
      '.yml' ||
      '.toml' ||
      '.ini' ||
      '.properties' =>
        FileVisual(icon: Icons.tune_rounded, color: AppColors.acid),
      '.sh' || '.zsh' || '.bash' || '.fish' => FileVisual(
        icon: Icons.terminal_rounded,
        color: const Color(0xFF8A9BB0),
      ),
      '.go' ||
      '.rs' ||
      '.c' ||
      '.h' ||
      '.cpp' ||
      '.cc' ||
      '.cs' ||
      '.swift' =>
        FileVisual(
          icon: Icons.code_rounded,
          color: const Color(0xFFA685FF),
        ),
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.webp' ||
      '.svg' ||
      '.ico' =>
        FileVisual(
          icon: Icons.image_outlined,
          color: const Color(0xFFE78AC9),
        ),
      '.mp4' ||
      '.mov' ||
      '.avi' ||
      '.mkv' => FileVisual(
        icon: Icons.movie_outlined,
        color: const Color(0xFFCC8CFF),
      ),
      '.mp3' ||
      '.wav' ||
      '.m4a' ||
      '.flac' => FileVisual(
        icon: Icons.audiotrack_rounded,
        color: const Color(0xFFDF82A9),
      ),
      '.zip' ||
      '.rar' ||
      '.7z' ||
      '.tar' ||
      '.gz' => FileVisual(
        icon: Icons.inventory_2_outlined,
        color: AppColors.amber,
      ),
      _ => FileVisual(
        icon: Icons.insert_drive_file_outlined,
        color: AppColors.textDim,
      ),
    };
  }
}
