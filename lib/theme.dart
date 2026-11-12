import 'package:flutter/material.dart';

/// Colour tokens, kept in sync with the "Tokens" collection in the Figma file.
class AppColors {
  const AppColors({
    required this.bg,
    required this.fg,
    required this.muted,
    required this.border,
    required this.surface,
    required this.accent,
  });

  final Color bg, fg, muted, border, surface, accent;

  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    fg: Color(0xFF000000),
    muted: Color(0xFF6B6B6B),
    border: Color(0xFFE5E5E5),
    surface: Color(0xFFF5F5F5),
    accent: Color(0xFF024944),
  );

  // #024944 is unreadable on black, so dark mode uses a lighter tint of it.
  static const dark = AppColors(
    bg: Color(0xFF000000),
    fg: Color(0xFFFFFFFF),
    muted: Color(0xFFA3A3A3),
    border: Color(0xFF2E2E2E),
    surface: Color(0xFF141414),
    accent: Color(0xFF5FB3A9),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.fg,
    onPrimary: c.bg,
    secondary: c.accent,
    onSecondary: c.bg,
    error: c.fg,
    onError: c.bg,
    surface: c.bg,
    onSurface: c.fg,
    surfaceContainerHighest: c.surface,
    outline: c.border,
    onSurfaceVariant: c.muted,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    dividerColor: c.border,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.fg,
        foregroundColor: c.bg,
        minimumSize: const Size.fromHeight(52),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.fg,
        side: BorderSide(color: c.border),
        minimumSize: const Size.fromHeight(52),
        shape: shape,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    // Green, so the Review count stays visible on the black active pill.
    badgeTheme: BadgeThemeData(backgroundColor: c.accent, textColor: c.bg),
    // The active tab is a solid pill in the text colour with the icon cut out
    // in the background colour, so it reads in both light and dark mode.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      indicatorColor: c.fg,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.bg : c.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? c.fg : c.muted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}
