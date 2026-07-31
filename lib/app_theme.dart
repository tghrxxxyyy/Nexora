import 'package:flutter/material.dart';

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

abstract final class AppColors {
  static const _dark = AppPalette(
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

  static const _light = AppPalette(
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

  static AppThemeMode _mode = AppThemeMode.light;

  static void use(AppThemeMode mode) => _mode = mode;

  static AppPalette get palette => _mode == AppThemeMode.dark ? _dark : _light;

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
}

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 100);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 520);
  static const curve = Cubic(0.22, 0.61, 0.36, 1);
  static const emphasized = Cubic(0.16, 1, 0.3, 1);
  static const navigationCurve = Cubic(0.22, 0.61, 0.36, 1);
}

ThemeData buildAppTheme(AppThemeMode mode) {
  AppColors.use(mode);
  final brightness = mode == AppThemeMode.dark
      ? Brightness.dark
      : Brightness.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.signal,
    brightness: brightness,
    surface: AppColors.surface,
    primary: AppColors.signal,
    secondary: AppColors.acid,
    error: AppColors.coral,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    fontFamily: 'MapleMonoCN',
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Segoe UI', 'sans-serif'],
    textTheme: TextTheme(
      displaySmall: TextStyle(
        color: AppColors.text,
        fontSize: 34,
        fontWeight: FontWeight.w300,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: AppColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: AppColors.text,
        fontSize: 15,
        height: 1.6,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        color: AppColors.text,
        fontSize: 13,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        height: 1.35,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: AppColors.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    dividerColor: AppColors.line.withValues(alpha: 0.28),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AppColors.signal.withValues(alpha: 0.035),
    focusColor: AppColors.signal.withValues(alpha: 0.10),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(
        color: AppColors.text,
        fontSize: 11,
        letterSpacing: 0,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceRaised.withValues(alpha: 0.84),
      hintStyle: TextStyle(color: AppColors.textDim, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceRaised,
      elevation: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? AppColors.signalDim.withValues(alpha: 0.88)
            : AppColors.lineStrong.withValues(alpha: 0.72),
      ),
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(8),
      crossAxisMargin: 5,
      mainAxisMargin: 6,
    ),
  );
}
