import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../services/app_theme_state.dart';
import '../../services/music_state.dart';
import '../../services/theme_image_cache.dart';

typedef ShowTopToast =
    void Function(String message, {Color border, IconData? icon});

void showSleepTimerSheet({
  required BuildContext context,
  required Duration selectedSleepTime,
  required ValueChanged<Duration> onSelectedSleepTimeChanged,
  required ValueChanged<Duration> onStartTimer,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      var tempSelectedSleepTime = selectedSleepTime;
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sleep Timer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 140,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.dark,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    child: CupertinoTimerPicker(
                      mode: CupertinoTimerPickerMode.hms,
                      initialTimerDuration: tempSelectedSleepTime,
                      onTimerDurationChanged: (Duration value) {
                        setModalState(() => tempSelectedSleepTime = value);
                        onSelectedSleepTimeChanged(value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [15, 30, 45, 60].map((minutes) {
                    return ActionChip(
                      backgroundColor: const Color(0xFF2A2A2A),
                      labelStyle: const TextStyle(color: Colors.white),
                      label: Text('${minutes}m'),
                      onPressed: () {
                        final selected = Duration(minutes: minutes);
                        onSelectedSleepTimeChanged(selected);
                        onStartTimer(selected);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      onStartTimer(tempSelectedSleepTime);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Start Timer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showThemePickerSheet({
  required BuildContext context,
  required ShowTopToast showTopToast,
}) {
  final currentIndex = AppThemeState.selectedThemeIndex.value;
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF161616),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Theme',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...List.generate(AppThemeState.presets.length, (index) {
              final preset = AppThemeState.presets[index];
              final selected = index == currentIndex;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    image: DecorationImage(
                      image: ThemeImageCache.provider(
                        preset.backgroundImageUrl,
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(
                  preset.name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? preset.accent : Colors.white54,
                ),
                onTap: () {
                  unawaited(
                    ThemeImageCache.prefetchUrl(preset.backgroundImageUrl),
                  );
                  AppThemeState.setTheme(index);
                  Navigator.pop(context);
                  showTopToast(
                    'Theme changed to ${preset.name}',
                    icon: Icons.palette_rounded,
                  );
                },
              );
            }),
          ],
        ),
      );
    },
  );
}

void showSpeedControlSheet({
  required BuildContext context,
  required AudioPlayer audioPlayer,
}) {
  var speed = audioPlayer.speed.clamp(0.5, 2.0);
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF191919),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Playback Speed ${speed.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  value: speed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: '${speed.toStringAsFixed(2)}x',
                  activeColor: Theme.of(context).colorScheme.secondary,
                  onChanged: (value) {
                    setModalState(() => speed = value);
                    audioPlayer.setSpeed(value);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void showVolumeControlSheet({
  required BuildContext context,
  required AudioPlayer audioPlayer,
}) {
  var volume = audioPlayer.volume.clamp(0.0, 1.0);
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF191919),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Volume ${(volume * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  value: volume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  activeColor: Theme.of(context).colorScheme.secondary,
                  onChanged: (value) {
                    setModalState(() => volume = value);
                    audioPlayer.setVolume(value);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
      : '$minutes:$seconds';
}

void showSongInfoSheet({
  required BuildContext context,
  required SongModel song,
  required AudioPlayer audioPlayer,
}) {
  final duration = audioPlayer.duration;
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      Widget infoRow(String label, String value) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Song Information',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            infoRow('Title', song.title),
            infoRow('Artist', song.artist ?? 'Unknown Artist'),
            infoRow('Album', song.album ?? 'Unknown Album'),
            infoRow(
              'Duration',
              duration == null ? 'Unknown' : _formatDuration(duration),
            ),
            infoRow('Song ID', song.id.toString()),
            const SizedBox(height: 10),
          ],
        ),
      );
    },
  );
}

void showAddToPlaylistSheet({
  required BuildContext context,
  required SongModel song,
  required ShowTopToast showTopToast,
}) {
  final playlists = MusicState.customPlaylists.value;
  if (playlists.isEmpty) {
    showTopToast(
      'Create a playlist first to add songs',
      icon: Icons.playlist_add_rounded,
      border: Colors.amberAccent,
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return ValueListenableBuilder<Map<String, List<SongModel>>>(
        valueListenable: MusicState.customPlaylists,
        builder: (context, customMap, _) {
          return ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  'Add to Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...customMap.keys.map((name) {
                final alreadyAdded = MusicState.isSongInCustomPlaylist(
                  name,
                  song,
                );
                return ListTile(
                  leading: Icon(
                    alreadyAdded
                        ? Icons.check_circle
                        : Icons.playlist_add_rounded,
                    color: alreadyAdded
                        ? Theme.of(context).colorScheme.secondary
                        : Colors.white60,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    alreadyAdded ? 'Already added' : 'Tap to add',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () {
                    final added = MusicState.addSongToCustomPlaylist(
                      name,
                      song,
                    );
                    Navigator.pop(context);
                    showTopToast(
                      added ? 'Added to "$name"' : 'Already in "$name"',
                      icon: added
                          ? Icons.check_circle
                          : Icons.info_outline_rounded,
                      border: added
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.amberAccent,
                    );
                  },
                );
              }),
            ],
          );
        },
      );
    },
  );
}

void showMoreActionsSheet({
  required BuildContext context,
  required AudioPlayer audioPlayer,
  required SongModel currentSong,
  required ShowTopToast showTopToast,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF171717),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded, color: Colors.white70),
            title: const Text(
              'Playback Speed',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              showSpeedControlSheet(context: context, audioPlayer: audioPlayer);
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_rounded, color: Colors.white70),
            title: const Text(
              'Playback Volume',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              showVolumeControlSheet(
                context: context,
                audioPlayer: audioPlayer,
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white70,
            ),
            title: const Text(
              'Song Information',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              showSongInfoSheet(
                context: context,
                song: currentSong,
                audioPlayer: audioPlayer,
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.playlist_add_rounded,
              color: Colors.white70,
            ),
            title: const Text(
              'Add to Playlist',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              showAddToPlaylistSheet(
                context: context,
                song: currentSong,
                showTopToast: showTopToast,
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}
