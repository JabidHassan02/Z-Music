import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MusicState {
  static final ValueNotifier<List<SongModel>> favorites = ValueNotifier([]);
  static final ValueNotifier<List<SongModel>> recentlyPlayed = ValueNotifier(
    [],
  );

  // Holds user-created playlists (Name -> List of Songs)
  static final ValueNotifier<Map<String, List<SongModel>>> customPlaylists =
      ValueNotifier({});

  static late SharedPreferences _prefs;

  static Future<void> init(List<SongModel> allDeviceSongs) async {
    _prefs = await SharedPreferences.getInstance();

    final List<String> favIds = _prefs.getStringList('favorites') ?? [];
    final List<String> recentIds =
        _prefs.getStringList('recently_played') ?? [];

    favorites.value = allDeviceSongs
        .where((song) => favIds.contains(song.id.toString()))
        .toList();

    final loadedRecents = <SongModel>[];
    final seenRecentSongIds = <int>{};
    for (String idStr in recentIds) {
      try {
        final song = allDeviceSongs.firstWhere((s) => s.id.toString() == idStr);
        if (seenRecentSongIds.contains(song.id)) {
          continue;
        }
        seenRecentSongIds.add(song.id);
        loadedRecents.add(song);
      } catch (e) {
        debugPrint('Skipped missing recent song id: $idStr');
      }
    }
    recentlyPlayed.value = loadedRecents;
    _prefs.setStringList(
      'recently_played',
      loadedRecents.map((song) => song.id.toString()).toList(),
    );

    // Load Custom Playlists
    final String? playlistsJson = _prefs.getString('custom_playlists');
    if (playlistsJson != null) {
      final Map<String, dynamic> decoded = jsonDecode(playlistsJson);
      Map<String, List<SongModel>> loadedPlaylists = {};
      decoded.forEach((key, value) {
        final ids = List<String>.from(value);
        final songs = <SongModel>[];
        for (final id in ids) {
          try {
            songs.add(allDeviceSongs.firstWhere((s) => s.id.toString() == id));
          } catch (e) {
            debugPrint('Skipped missing song id in playlist "$key": $id');
          }
        }
        loadedPlaylists[key] = songs;
      });
      customPlaylists.value = loadedPlaylists;
    }
  }

  static void toggleFavorite(SongModel song) {
    final currentList = List<SongModel>.from(favorites.value);
    currentList.any((s) => s.id == song.id)
        ? currentList.removeWhere((s) => s.id == song.id)
        : currentList.add(song);
    favorites.value = currentList;
    _prefs.setStringList(
      'favorites',
      currentList.map((s) => s.id.toString()).toList(),
    );
  }

  static bool isFavorite(SongModel song) =>
      favorites.value.any((s) => s.id == song.id);

  static void addRecent(SongModel song) {
    final currentList = List<SongModel>.from(recentlyPlayed.value);
    if (currentList.isNotEmpty && currentList.first.id == song.id) {
      return;
    }
    currentList.removeWhere((s) => s.id == song.id);
    currentList.insert(0, song);
    if (currentList.length > 5) currentList.removeLast();
    recentlyPlayed.value = currentList;
    _prefs.setStringList(
      'recently_played',
      currentList.map((s) => s.id.toString()).toList(),
    );
  }

  // --- CUSTOM PLAYLIST METHODS ---
  static void createPlaylist(String name) {
    final currentMap = Map<String, List<SongModel>>.from(customPlaylists.value);
    if (!currentMap.containsKey(name)) {
      currentMap[name] = [];
      customPlaylists.value = currentMap;
      _saveCustomPlaylists();
    }
  }

  static void deletePlaylist(String name) {
    final currentMap = Map<String, List<SongModel>>.from(customPlaylists.value);
    currentMap.remove(name);
    customPlaylists.value = currentMap;
    _saveCustomPlaylists();
  }

  static bool addSongToCustomPlaylist(String playlistName, SongModel song) {
    final currentMap = Map<String, List<SongModel>>.from(customPlaylists.value);
    final existingSongs = currentMap[playlistName];
    if (existingSongs == null) return false;

    if (existingSongs.any((s) => s.id == song.id)) return false;

    final updatedSongs = List<SongModel>.from(existingSongs)..add(song);
    currentMap[playlistName] = updatedSongs;
    customPlaylists.value = currentMap;
    _saveCustomPlaylists();
    return true;
  }

  static int removeSongsFromCustomPlaylist(
    String playlistName,
    Set<int> songIds,
  ) {
    if (songIds.isEmpty) return 0;
    final currentMap = Map<String, List<SongModel>>.from(customPlaylists.value);
    final existingSongs = currentMap[playlistName];
    if (existingSongs == null) return 0;

    final beforeLength = existingSongs.length;
    final updatedSongs = List<SongModel>.from(existingSongs)
      ..removeWhere((s) => songIds.contains(s.id));
    final removedCount = beforeLength - updatedSongs.length;

    if (removedCount > 0) {
      currentMap[playlistName] = updatedSongs;
      customPlaylists.value = currentMap;
      _saveCustomPlaylists();
    }

    return removedCount;
  }

  static bool removeSongFromCustomPlaylist(
    String playlistName,
    SongModel song,
  ) {
    return removeSongsFromCustomPlaylist(playlistName, {song.id}) > 0;
  }

  static bool isSongInCustomPlaylist(String playlistName, SongModel song) {
    final songs = customPlaylists.value[playlistName];
    if (songs == null) return false;
    return songs.any((s) => s.id == song.id);
  }

  static void _saveCustomPlaylists() {
    Map<String, List<String>> toSave = {};
    customPlaylists.value.forEach((key, songs) {
      toSave[key] = songs.map((s) => s.id.toString()).toList();
    });
    _prefs.setString('custom_playlists', jsonEncode(toSave));
  }
}
