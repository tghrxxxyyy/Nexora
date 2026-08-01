import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Thrown when a theme JSON document cannot be parsed into a usable definition.
class ThemeFormatException implements Exception {
  const ThemeFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses theme JSON documents into [AppThemeDefinition] instances and
/// serializes definitions back to JSON for persistence.
class ThemeLoader {
  const ThemeLoader();

  /// Light palette used when an imported theme omits a color field.
  static final AppPalette _lightFallback =
      AppColors.builtinThemes.first.palette;

  /// Parses a theme JSON document into a definition.
  ///
  /// Throws [ThemeFormatException] when the document is not a JSON object,
  /// lacks the required `colors` map, or contains a malformed hex string.
  /// Missing color fields silently fall back to the built-in Light palette.
  AppThemeDefinition parse(
    String source, {
    String? fallbackId,
    String? fallbackName,
  }) {
    Object decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ThemeFormatException('JSON 解析失败: ${error.message}');
    }
    if (decoded is! Map) {
      throw const ThemeFormatException('顶层应为 JSON 对象');
    }
    final root = Map<String, dynamic>.from(decoded);

    final colorsRaw = root['colors'];
    if (colorsRaw is! Map) {
      throw const ThemeFormatException('缺少 colors 字段或格式不正确');
    }
    final colors = Map<String, dynamic>.from(colorsRaw);
    final palette = _buildPalette(colors);

    final idRaw = (root['id'] as String?)?.trim();
    final id = (idRaw == null || idRaw.isEmpty) ? (fallbackId ?? 'theme') : idRaw;
    final nameRaw = (root['name'] as String?)?.trim();
    final name = (nameRaw == null || nameRaw.isEmpty) ? (fallbackName ?? id) : nameRaw;

    final fontRaw = (root['fontFamily'] as String?)?.trim();
    final fontFamily = (fontRaw == null || fontRaw.isEmpty) ? null : fontRaw;

    final radiusRaw = root['radiusFactor'];
    final radiusFactor = radiusRaw is num ? radiusRaw.toDouble() : null;

    return AppThemeDefinition(
      id: id,
      name: name,
      palette: palette,
      fontFamily: fontFamily,
      radiusFactor: radiusFactor,
      builtIn: false,
    );
  }

  AppPalette _buildPalette(Map<String, dynamic> colors) {
    Color read(String field) {
      final raw = colors[field];
      if (raw is String && raw.trim().isNotEmpty) {
        return _parseHex(raw, field);
      }
      return _lookupFallback(field);
    }

    return AppPalette(
      background: read('background'),
      backgroundRaised: read('backgroundRaised'),
      surface: read('surface'),
      surfaceRaised: read('surfaceRaised'),
      surfaceHover: read('surfaceHover'),
      line: read('line'),
      lineStrong: read('lineStrong'),
      text: read('text'),
      textMuted: read('textMuted'),
      textDim: read('textDim'),
      signal: read('signal'),
      signalDim: read('signalDim'),
      acid: read('acid'),
      coral: read('coral'),
      amber: read('amber'),
      selection: read('selection'),
    );
  }

  Color _lookupFallback(String field) {
    final fallback = _lightFallback;
    switch (field) {
      case 'background':
        return fallback.background;
      case 'backgroundRaised':
        return fallback.backgroundRaised;
      case 'surface':
        return fallback.surface;
      case 'surfaceRaised':
        return fallback.surfaceRaised;
      case 'surfaceHover':
        return fallback.surfaceHover;
      case 'line':
        return fallback.line;
      case 'lineStrong':
        return fallback.lineStrong;
      case 'text':
        return fallback.text;
      case 'textMuted':
        return fallback.textMuted;
      case 'textDim':
        return fallback.textDim;
      case 'signal':
        return fallback.signal;
      case 'signalDim':
        return fallback.signalDim;
      case 'acid':
        return fallback.acid;
      case 'coral':
        return fallback.coral;
      case 'amber':
        return fallback.amber;
      case 'selection':
        return fallback.selection;
      default:
        return const Color(0xFF000000);
    }
  }

  Color _parseHex(String raw, String field) {
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.isEmpty) {
      throw ThemeFormatException('$field 的颜色值为空');
    }
    final expanded = hex.length == 3
        ? hex.split('').map((char) => '$char$char').join()
        : hex;
    if (expanded.length != 6 && expanded.length != 8) {
      throw ThemeFormatException('$field 的颜色值格式无效: "$raw"');
    }
    final value = int.tryParse(expanded, radix: 16);
    if (value == null) {
      throw ThemeFormatException('$field 的颜色值无法解析: "$raw"');
    }
    if (expanded.length == 6) {
      return Color(0xFF000000 | value);
    }
    return Color(value);
  }

  /// Serializes a definition back to JSON. Used when persisting an import.
  Map<String, dynamic> toJson(AppThemeDefinition theme) {
    final p = theme.palette;
    return {
      'id': theme.id,
      'name': theme.name,
      'fontFamily': ?theme.fontFamily,
      'radiusFactor': ?theme.radiusFactor,
      'colors': {
        'background': _toHex(p.background),
        'backgroundRaised': _toHex(p.backgroundRaised),
        'surface': _toHex(p.surface),
        'surfaceRaised': _toHex(p.surfaceRaised),
        'surfaceHover': _toHex(p.surfaceHover),
        'line': _toHex(p.line),
        'lineStrong': _toHex(p.lineStrong),
        'text': _toHex(p.text),
        'textMuted': _toHex(p.textMuted),
        'textDim': _toHex(p.textDim),
        'signal': _toHex(p.signal),
        'signalDim': _toHex(p.signalDim),
        'acid': _toHex(p.acid),
        'coral': _toHex(p.coral),
        'amber': _toHex(p.amber),
        'selection': _toHex(p.selection),
      },
    };
  }

  static String _toHex(Color color) {
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final rgb = (r << 16) | (g << 8) | b;
    if (a == 0xFF) {
      return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }
    final argb = (a << 24) | rgb;
    return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
