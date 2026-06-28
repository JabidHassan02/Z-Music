import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/app_theme_state.dart';
import 'services/theme_image_cache.dart';
import 'screens/library_screen.dart'; // Import your screen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeState.init();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_app.channel.audio',
    androidNotificationChannelName: 'Z Music Playback',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_stat_music',
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  unawaited(
    ThemeImageCache.prefetchUrl(AppThemeState.current.backgroundImageUrl),
  );
  runApp(const ModernMusicApp());
}

class ModernMusicApp extends StatelessWidget {
  const ModernMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeState.selectedThemeIndex,
      builder: (context, index, _) {
        return MaterialApp(
          title: 'Z Music',
          theme: AppThemeState.buildMaterialTheme(AppThemeState.current),
          home: const MusicLibraryScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
