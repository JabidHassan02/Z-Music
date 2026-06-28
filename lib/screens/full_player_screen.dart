import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/app_theme_state.dart';
import '../services/music_state.dart';
import '../services/theme_image_cache.dart';
import 'full_player/full_player_sheets.dart';
import 'full_player/full_player_widgets.dart';

class FullPlayerScreen extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final ValueNotifier<SongModel?> currentSongNotifier;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const FullPlayerScreen({
    super.key,
    required this.audioPlayer,
    required this.currentSongNotifier,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  Timer? _sleepTimer;
  Duration _selectedSleepTime = Duration.zero;
  OverlayEntry? _toastEntry;
  String? _lastCachedThemeImageUrl;

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  String _formatProgress(Duration position, Duration duration) {
    return '${_formatDuration(position)}/${_formatDuration(duration)}';
  }

  void _skip(int seconds) {
    var newPosition = widget.audioPlayer.position + Duration(seconds: seconds);
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    final duration = widget.audioPlayer.duration;
    if (duration != null && newPosition > duration) {
      newPosition = duration;
    }
    widget.audioPlayer.seek(newPosition);
  }

  void _showTopToast(String message, {Color? border, IconData? icon}) {
    final preset = AppThemeState.current;
    final accentColor = border ?? preset.accent;
    _toastEntry?.remove();
    _toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: preset.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.78)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_toastEntry!);
    Future.delayed(const Duration(milliseconds: 1600), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  void _cacheThemeBackground(String imageUrl) {
    if (_lastCachedThemeImageUrl == imageUrl) return;
    _lastCachedThemeImageUrl = imageUrl;
    unawaited(ThemeImageCache.prefetchUrl(imageUrl));
    unawaited(precacheImage(ThemeImageCache.provider(imageUrl), context));
  }

  Future<void> _toggleRepeat() async {
    final currentMode = widget.audioPlayer.loopMode;
    if (currentMode == LoopMode.off) {
      await widget.audioPlayer.setLoopMode(LoopMode.all);
      _showTopToast('Loop all enabled', icon: Icons.repeat);
    } else if (currentMode == LoopMode.all) {
      await widget.audioPlayer.setLoopMode(LoopMode.one);
      _showTopToast('Repeat one enabled', icon: Icons.repeat_one);
    } else {
      await widget.audioPlayer.setLoopMode(LoopMode.off);
      _showTopToast('Repeat off', icon: Icons.repeat);
    }
    setState(() {});
  }

  void _startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    if (duration.inSeconds > 0) {
      _sleepTimer = Timer(duration, () => widget.audioPlayer.pause());
      _showTopToast(
        'Sleep in ${duration.inMinutes}m',
        icon: Icons.bedtime_rounded,
      );
    }
  }

  void _openSleepTimer() {
    showSleepTimerSheet(
      context: context,
      selectedSleepTime: _selectedSleepTime,
      onSelectedSleepTimeChanged: (value) => _selectedSleepTime = value,
      onStartTimer: _startSleepTimer,
    );
  }

  void _openThemePicker() {
    showThemePickerSheet(context: context, showTopToast: _showTopToast);
  }

  void _openMoreActions(SongModel currentSong) {
    showMoreActionsSheet(
      context: context,
      audioPlayer: widget.audioPlayer,
      currentSong: currentSong,
      showTopToast: _showTopToast,
    );
  }

  double _resolveProgressSize(double maxHeight) {
    const maxSize = 250.0;
    const minSize = 150.0;
    const reservedHeight = 250.0;
    final candidate = maxHeight - reservedHeight;
    return candidate.clamp(minSize, maxSize);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeState.selectedThemeIndex,
      builder: (context, _, __) {
        final preset = AppThemeState.current;
        _cacheThemeBackground(preset.backgroundImageUrl);
        return ValueListenableBuilder<SongModel?>(
          valueListenable: widget.currentSongNotifier,
          builder: (context, currentSong, child) {
            if (currentSong == null) return const SizedBox.shrink();

            return Scaffold(
              backgroundColor: preset.background,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 72,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                title: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Now Playing',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                centerTitle: true,
              ),
              body: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: ThemeImageCache.provider(preset.backgroundImageUrl),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.38),
                        preset.background.withValues(alpha: 0.86),
                        const Color(0xFF0F0F0F),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final progressSize = _resolveProgressSize(
                          constraints.maxHeight,
                        );
                        return Column(
                          children: [
                            const SizedBox(height: 18),
                            FullPlayerSongHeader(song: currentSong),
                            const Spacer(),
                            FullPlayerProgressSection(
                              audioPlayer: widget.audioPlayer,
                              accentColor: preset.accent,
                              sliderSize: progressSize,
                              song: currentSong,
                              formatProgress: _formatProgress,
                            ),
                            const Spacer(),
                            ValueListenableBuilder<List<SongModel>>(
                              valueListenable: MusicState.favorites,
                              builder: (context, favorites, _) {
                                return FullPlayerActionButtonsRow(
                                  isFavorite: MusicState.isFavorite(currentSong),
                                  loopMode: widget.audioPlayer.loopMode,
                                  accentColor: preset.accent,
                                  onFavorite: () =>
                                      MusicState.toggleFavorite(currentSong),
                                  onTheme: _openThemePicker,
                                  onSleep: _openSleepTimer,
                                  onMore: () => _openMoreActions(currentSong),
                                  onRepeat: _toggleRepeat,
                                );
                              },
                            ),
                            FullPlayerTransportControls(
                              audioPlayer: widget.audioPlayer,
                              accentColor: preset.accent,
                              onPrevious: widget.onPrevious,
                              onNext: widget.onNext,
                              onSkip: _skip,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
