import 'package:flutter/material.dart';

/// 保留仅作向后兼容:读取老 session 中的 `themeMode` 字段时映射到对应内置主题 id。
enum AppThemeMode { light, dark }

class AppPalette {
  const AppPalette({
    required this.background,
    required this.backgroundRaised,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.signal,
    required this.signalDim,
    required this.acid,
    required this.coral,
    required this.amber,
    required this.selection,
  });

  final Color background;
  final Color backgroundRaised;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color textMuted;
  final Color textDim;
  final Color signal;
  final Color signalDim;
  final Color acid;
  final Color coral;
  final Color amber;
  final Color selection;
}

/// A complete theme: a color palette plus optional font and corner-radius tweaks.
class AppThemeDefinition {
  const AppThemeDefinition({
    required this.id,
    required this.name,
    required this.palette,
    this.fontFamily,
    this.radiusFactor,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final AppPalette palette;
  final String? fontFamily;
  final double? radiusFactor;
  final bool builtIn;

  AppThemeDefinition copyWith({String? id, String? name}) {
    return AppThemeDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      palette: palette,
      fontFamily: fontFamily,
      radiusFactor: radiusFactor,
      builtIn: builtIn,
    );
  }
}

abstract final class AppColors {
  static const _lightPalette = AppPalette(
    background: Color(0xFFFFFFFF),
    backgroundRaised: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F8FB),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF1F6FB),
    line: Color(0xFFE9EFF5),
    lineStrong: Color(0xFFD8E3EE),
    text: Color(0xFF263440),
    textMuted: Color(0xFF667584),
    textDim: Color(0xFF9BA8B5),
    signal: Color(0xFF3298E0),
    signalDim: Color(0xFF79BDEB),
    acid: Color(0xFF667E9C),
    coral: Color(0xFFE97878),
    amber: Color(0xFFF1B454),
    selection: Color(0x263298E0),
  );

  static const _darkPalette = AppPalette(
    background: Color(0xFF0C0F11),
    backgroundRaised: Color(0xFF10151A),
    surface: Color(0xFF141B20),
    surfaceRaised: Color(0xFF1A2228),
    surfaceHover: Color(0xFF202A30),
    line: Color(0xFF202B31),
    lineStrong: Color(0xFF2C3A42),
    text: Color(0xFFF1F4F5),
    textMuted: Color(0xFFAAB6BB),
    textDim: Color(0xFF708087),
    signal: Color(0xFF93D9C4),
    signalDim: Color(0xFF5A9688),
    acid: Color(0xFFC4D893),
    coral: Color(0xFFE5957C),
    amber: Color(0xFFD8B779),
    selection: Color(0x4293D9C4),
  );

  static const _nordPalette = AppPalette(
    background: Color(0xFF2E3440),
    backgroundRaised: Color(0xFF3B4252),
    surface: Color(0xFF3B4252),
    surfaceRaised: Color(0xFF3B4252),
    surfaceHover: Color(0xFF434C5E),
    line: Color(0xFF434C5E),
    lineStrong: Color(0xFF4C566A),
    text: Color(0xFFECEFF4),
    textMuted: Color(0xFFD8DEE9),
    textDim: Color(0xFF81A1C1),
    signal: Color(0xFF88C0D0),
    signalDim: Color(0xFF81A1C1),
    acid: Color(0xFFA3BE8C),
    coral: Color(0xFFBF616A),
    amber: Color(0xFFEBCB8B),
    selection: Color(0x4288C0D0),
  );

  static const _draculaPalette = AppPalette(
    background: Color(0xFF282A36),
    backgroundRaised: Color(0xFF21222C),
    surface: Color(0xFF44475A),
    surfaceRaised: Color(0xFF282A36),
    surfaceHover: Color(0xFF484B5D),
    line: Color(0xFF44475A),
    lineStrong: Color(0xFF6272A4),
    text: Color(0xFFF8F8F2),
    textMuted: Color(0xFFBCC2CD),
    textDim: Color(0xFF6272A4),
    signal: Color(0xFFBD93F9),
    signalDim: Color(0xFF8BE9FD),
    acid: Color(0xFF50FA7B),
    coral: Color(0xFFFF5555),
    amber: Color(0xFFF1FA8C),
    selection: Color(0x44BD93F9),
  );

  static const _solarizedPalette = AppPalette(
    background: Color(0xFFFDF6E3),
    backgroundRaised: Color(0xFFEEE8D5),
    surface: Color(0xFFEEE8D5),
    surfaceRaised: Color(0xFFFDF6E3),
    surfaceHover: Color(0xFFE5DDC6),
    line: Color(0xFFEEE8D5),
    lineStrong: Color(0xFF93A1A1),
    text: Color(0xFF586E75),
    textMuted: Color(0xFF657B83),
    textDim: Color(0xFF93A1A1),
    signal: Color(0xFF268BD2),
    signalDim: Color(0xFF2AA198),
    acid: Color(0xFF859900),
    coral: Color(0xFFDC322F),
    amber: Color(0xFFB58900),
    selection: Color(0x26268BD2),
  );

  static const _githubPalette = AppPalette(
    background: Color(0xFFFFFFFF),
    backgroundRaised: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F8FA),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFEAEEF2),
    line: Color(0xFFD0D7DE),
    lineStrong: Color(0xFFAFB8C1),
    text: Color(0xFF1F2328),
    textMuted: Color(0xFF656D76),
    textDim: Color(0xFF8C959F),
    signal: Color(0xFF0969DA),
    signalDim: Color(0xFF218BFF),
    acid: Color(0xFF1A7F37),
    coral: Color(0xFFCF222E),
    amber: Color(0xFF9A6700),
    selection: Color(0x260969DA),
  );

  static const _githubDarkPalette = AppPalette(
    background: Color(0xFF0D1117),
    backgroundRaised: Color(0xFF161B22),
    surface: Color(0xFF21262D),
    surfaceRaised: Color(0xFF30363D),
    surfaceHover: Color(0xFF30363D),
    line: Color(0xFF30363D),
    lineStrong: Color(0xFF484F58),
    text: Color(0xFFE6EDF3),
    textMuted: Color(0xFF7D8590),
    textDim: Color(0xFF6E7681),
    signal: Color(0xFF2F81F7),
    signalDim: Color(0xFF1F6FEB),
    acid: Color(0xFF3FB950),
    coral: Color(0xFFFF7B72),
    amber: Color(0xFFD29922),
    selection: Color(0x442F81F7),
  );

  static const _monokaiPalette = AppPalette(
    background: Color(0xFF272822),
    backgroundRaised: Color(0xFF1E1F1C),
    surface: Color(0xFF3E3D32),
    surfaceRaised: Color(0xFF272822),
    surfaceHover: Color(0xFF49483E),
    line: Color(0xFF3E3D32),
    lineStrong: Color(0xFF49483E),
    text: Color(0xFFF8F8F2),
    textMuted: Color(0xFFC8C8BE),
    textDim: Color(0xFF75715E),
    signal: Color(0xFF66D9EF),
    signalDim: Color(0xFF93E2F5),
    acid: Color(0xFFA6E22E),
    coral: Color(0xFFF92672),
    amber: Color(0xFFE6DB74),
    selection: Color(0x4466D9EF),
  );

  static const List<AppThemeDefinition> builtinThemes = [
    AppThemeDefinition(
      id: 'light',
      name: 'Light',
      palette: _lightPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'dark',
      name: 'Dark',
      palette: _darkPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'nord',
      name: 'Nord',
      palette: _nordPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'dracula',
      name: 'Dracula',
      palette: _draculaPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'solarized',
      name: 'Solarized',
      palette: _solarizedPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'github',
      name: 'GitHub',
      palette: _githubPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'github-dark',
      name: 'GitHub Dark',
      palette: _githubDarkPalette,
      builtIn: true,
    ),
    AppThemeDefinition(
      id: 'monokai',
      name: 'Monokai',
      palette: _monokaiPalette,
      builtIn: true,
    ),
  ];

  static AppThemeDefinition _current = builtinThemes.first;

  static AppThemeDefinition get current => _current;

  /// Applies a resolved theme definition. Call before rebuilding the widget tree.
  static void apply(AppThemeDefinition theme) {
    _current = theme;
  }

  /// Backwards-compatible entry retained so older callers that still pass an
  /// [AppThemeMode] can map it onto the matching built-in theme id.
  static void use(AppThemeMode mode) {
    final id = mode == AppThemeMode.dark ? 'dark' : 'light';
    _current = builtinThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => builtinThemes.first,
    );
  }

  static AppPalette get palette => _current.palette;
  static String get fontFamily => _current.fontFamily ?? 'MapleMonoCN';
  static double get radiusFactor => _current.radiusFactor ?? 1.0;

  static Color get background => palette.background;
  static Color get backgroundRaised => palette.backgroundRaised;
  static Color get surface => palette.surface;
  static Color get surfaceRaised => palette.surfaceRaised;
  static Color get surfaceHover => palette.surfaceHover;
  static Color get line => palette.line;
  static Color get lineStrong => palette.lineStrong;
  static Color get text => palette.text;
  static Color get textMuted => palette.textMuted;
  static Color get textDim => palette.textDim;
  static Color get signal => palette.signal;
  static Color get signalDim => palette.signalDim;
  static Color get acid => palette.acid;
  static Color get coral => palette.coral;
  static Color get amber => palette.amber;
  static Color get selection => palette.selection;

  /// Scales a base corner radius by the current theme's radius factor.
  static double radius(double base) => base * radiusFactor;
}

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 100);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 520);
  static const curve = Cubic(0.22, 0.61, 0.36, 1);
  static const emphasized = Cubic(0.16, 1, 0.3, 1);
  static const navigationCurve = Cubic(0.22, 0.61, 0.36, 1);
}

ThemeData buildAppTheme(AppThemeDefinition theme) {
  AppColors.apply(theme);
  final palette = theme.palette;
  final brightness = palette.background.computeLuminance() < 0.5
      ? Brightness.dark
      : Brightness.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: palette.signal,
    brightness: brightness,
    surface: palette.surface,
    primary: palette.signal,
    secondary: palette.acid,
    error: palette.coral,
  );
  final radius = AppColors.radiusFactor;
  final fontFamily = theme.fontFamily ?? 'MapleMonoCN';

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    fontFamily: fontFamily,
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Segoe UI', 'sans-serif'],
    textTheme: TextTheme(
      displaySmall: TextStyle(
        color: palette.text,
        fontSize: 34,
        fontWeight: FontWeight.w300,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: palette.text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: palette.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: palette.text,
        fontSize: 15,
        height: 1.6,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        color: palette.text,
        fontSize: 13,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        height: 1.35,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: palette.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    dividerColor: palette.line.withValues(alpha: 0.28),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: palette.signal.withValues(alpha: 0.035),
    focusColor: palette.signal.withValues(alpha: 0.10),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.signal,
      selectionColor: palette.selection,
      selectionHandleColor: palette.signal,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(4 * radius),
      ),
      textStyle: TextStyle(
        color: palette.text,
        fontSize: 11,
        letterSpacing: 0,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: palette.surfaceRaised.withValues(alpha: 0.84),
      hintStyle: TextStyle(color: palette.textDim, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      prefixIconColor: palette.textMuted,
      suffixIconColor: palette.textMuted,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6 * radius),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surfaceRaised,
      elevation: 18,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4 * radius),
      ),
      textStyle: TextStyle(color: palette.text, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? palette.signalDim.withValues(alpha: 0.88)
            : palette.lineStrong.withValues(alpha: 0.72),
      ),
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(8),
      crossAxisMargin: 5,
      mainAxisMargin: 6,
    ),
  );
}
