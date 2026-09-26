import 'package:flutter/material.dart';

class CholoColors {
  static const green = Color(0xFF0B8F5A);
  static const greenDark = Color(0xFF066B43);
  static const sun = Color(0xFFFFC93C);
  static const ink = Color(0xFF14201B);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: CholoColors.green,
    brightness: brightness,
    primary: brightness == Brightness.light ? CholoColors.green : null,
    secondary: CholoColors.sun,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
