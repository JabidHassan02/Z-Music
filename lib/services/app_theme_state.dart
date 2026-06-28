import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemePreset {
  final String name;
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color card;
  final String backgroundImageUrl;

  const AppThemePreset({
    required this.name,
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.card,
    required this.backgroundImageUrl,
  });
}

class AppThemeState {
  static const String _themeIndexKey = 'theme_index';
  static final ValueNotifier<int> selectedThemeIndex = ValueNotifier<int>(0);
  static late SharedPreferences _prefs;

  static const List<AppThemePreset> presets = [
    AppThemePreset(
      name: 'Forest',
      primary: Color(0xFF38A169),
      accent: Color(0xFF68D391),
      background: Color(0xFF0F1712),
      surface: Color(0xFF1B2A21),
      card: Color(0xFF233328),
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=1200&q=80',
    ),
    AppThemePreset(
      name: 'Ocean',
      primary: Color(0xFF0EA5E9),
      accent: Color(0xFF38BDF8),
      background: Color(0xFF081A22),
      surface: Color(0xFF0E2A36),
      card: Color(0xFF153847),
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=1200&q=80',
    ),
    AppThemePreset(
      name: 'Sunset',
      primary: Color(0xFFF97316),
      accent: Color(0xFFFB7185),
      background: Color(0xFF22130D),
      surface: Color(0xFF3A2015),
      card: Color(0xFF4B2A1C),
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1472120435266-53107fd0c44a?auto=format&fit=crop&w=1200&q=80',
    ),
    AppThemePreset(
      name: 'Desert',
      primary: Color(0xFFEAB308),
      accent: Color(0xFFF59E0B),
      background: Color(0xFF1F1A11),
      surface: Color(0xFF332A1B),
      card: Color(0xFF473723),
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1509316785289-025f5b846b35?auto=format&fit=crop&w=1200&q=80',
    ),
    AppThemePreset(
      name: 'Aurora',
      primary: Color(0xFF8B5CF6),
      accent: Color(0xFF22D3EE),
      background: Color(0xFF101225),
      surface: Color(0xFF1B2140),
      card: Color(0xFF242C52),
      backgroundImageUrl:
          'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=1200&q=80',
    ),
  ];

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs.getInt(_themeIndexKey) ?? 0;
    if (stored >= 0 && stored < presets.length) {
      selectedThemeIndex.value = stored;
    }
  }

  static AppThemePreset get current => presets[selectedThemeIndex.value];

  static Future<void> setTheme(int index) async {
    if (index < 0 || index >= presets.length) return;
    selectedThemeIndex.value = index;
    await _prefs.setInt(_themeIndexKey, index);
  }

  static ThemeData buildMaterialTheme(AppThemePreset preset) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: preset.background,
      cardColor: preset.card,
      primaryColor: preset.primary,
      colorScheme: ColorScheme.dark(
        primary: preset.primary,
        secondary: preset.accent,
        surface: preset.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: preset.surface,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}
