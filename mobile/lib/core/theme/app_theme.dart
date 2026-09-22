import 'package:flutter/material.dart';

const paletteBackground = Color(0xFF0D1013);
const surface = Color(0xFF171C20);
const line = Color(0xFF293037);
const ink = Color(0xFFF0F3EF);
const muted = Color(0xFF99A4AA);
const accent = Color(0xFFC5F277);
const positive = Color(0xFF68D9AE);
const negative = Color(0xFFF1848C);
const amber = Color(0xFFE9BB72);

final tickTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: paletteBackground,
  colorScheme: const ColorScheme.dark(
    primary: accent,
    surface: surface,
    onSurface: ink,
    secondary: positive,
  ),
  useMaterial3: true,
  dividerColor: line,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: ink, fontSize: 13),
    bodySmall: TextStyle(color: muted, fontSize: 11),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      backgroundColor: accent,
      foregroundColor: paletteBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: ink,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

TextStyle numbers({
  double size = 13,
  Color color = ink,
  FontWeight weight = FontWeight.w500,
}) => TextStyle(
  fontSize: size,
  color: color,
  fontWeight: weight,
  fontFeatures: const [FontFeature.tabularFigures()],
);
