import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/music_state.dart';
import '../widgets/mini_player.dart';
import 'playlist/widgets/add_songs_to_playlist_sheet.dart';
import 'playlist/widgets/playlist_square_card.dart';

typedef PlaySongCallback =
    Future<void> Function(SongModel song, {List<SongModel>? queue});

class PlaylistScreen extends StatefulWidget {
  final PlaySongCallback onPlaySong;
  final List<SongModel> allSongs;
  final AudioPlayer audioPlayer;
  final ValueNotifier<SongModel?> currentSongNotifier;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onOpenFullPlayer;

  const PlaylistScreen({
    super.key,
    required this.onPlaySong,
    required this.allSongs,
    required this.audioPlayer,
    required this.currentSongNotifier,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onOpenFullPlayer,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final Set<String> _selectedPlaylists = {};
  OverlayEntry? _statusEntry;
  StreamSubscription<PlayerState>? _playerStateSub;

  bool get _isSelectionMode => _selectedPlaylists.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.currentSongNotifier.addListener(_refreshMiniPlayer);
    _playerStateSub = widget.audioPlayer.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    widget.currentSongNotifier.removeListener(_refreshMiniPlayer);
    _statusEntry?.remove();
    super.dispose();
  }

  void _refreshMiniPlayer() {
    if (mounted) setState(() {});
  }

  void _showTopStatus({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    _statusEntry?.remove();
    _statusEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 18,
        right: 18,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF202020).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

    Overlay.of(context).insert(_statusEntry!);
    Future.delayed(const Duration(milliseconds: 1500), () {
      _statusEntry?.remove();
      _statusEntry = null;
    });
  }

  void _toggleSelection(String playlistName) {
    setState(() {
      if (_selectedPlaylists.contains(playlistName)) {
        _selectedPlaylists.remove(playlistName);
      } else {
        _selectedPlaylists.add(playlistName);
      }
    });
  }

  void _deleteSelectedPlaylists() {
    final deletedCount = _selectedPlaylists.length;
    for (final name in _selectedPlaylists) {
      MusicState.deletePlaylist(name);
    }
    setState(() => _selectedPlaylists.clear());

    _showTopStatus(
      message: deletedCount == 1 ? 'Playlist deleted' : '$deletedCount playlists deleted',
      icon: Icons.delete_forever_rounded,
      color: Colors.redAccent,
    );
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final playlistName = controller.text.trim();
              if (playlistName.isNotEmpty) {
                MusicState.createPlaylist(playlistName);
                _showTopStatus(
                  message: 'Playlist "$playlistName" created',
                  icon: Icons.library_add_check_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                );
              }
              Navigator.pop(context);
            },
            child: Text('Create', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ),
        ],
      ),
    );
  }

  void _showCustomPlaylistDetails(
    String playlistName,
    List<SongModel> songs, {
    bool isBuiltIn = false,
  }) {
    final selectedSongIds = <int>{};

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedSongIds.isNotEmpty ? '${selectedSongIds.length} Selected' : playlistName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (!isBuiltIn)
                      selectedSongIds.isNotEmpty
                          ? Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70),
                                  onPressed: () => setModalState(() => selectedSongIds.clear()),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () {
                                    final removedCount =
                                        MusicState.removeSongsFromCustomPlaylist(
                                      playlistName,
                                      Set<int>.from(selectedSongIds),
                                    );
                                    setModalState(() => selectedSongIds.clear());
                                    if (removedCount > 0) {
                                      _showTopStatus(
                                        message: removedCount == 1
                                            ? '1 song removed from "$playlistName"'
                                            : '$removedCount songs removed from "$playlistName"',
                                        icon: Icons.remove_circle,
                                        color: Colors.redAccent,
                                      );
                                    }
                                  },
                                ),
                              ],
                            )
                          : IconButton(
                              icon: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.secondary, size: 32),
                              onPressed: () => _showAddSongsToPlaylist(playlistName),
                            ),
                  ],
                ),
              ),
              Expanded(
                child: isBuiltIn
                    ? (songs.isEmpty
                        ? const Center(
                            child: Text(
                              'No songs here yet.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: songs.length,
                            itemBuilder: (context, index) {
                              final song = songs[index];
                              return ListTile(
                                leading: Icon(Icons.music_note, color: Theme.of(context).colorScheme.secondary),
                                title: Text(song.title, style: const TextStyle(color: Colors.white), maxLines: 1),
                                subtitle: Text(song.artist ?? 'Unknown', style: const TextStyle(color: Colors.white54)),
                                onTap: () {
                                  Navigator.pop(context);
                                  unawaited(
                                    widget.onPlaySong(
                                      song,
                                      queue: List<SongModel>.from(songs),
                                    ),
                                  );
                                },
                              );
                            },
                          ))
                    : ValueListenableBuilder<Map<String, List<SongModel>>>(
                        valueListenable: MusicState.customPlaylists,
                        builder: (context, customMap, _) {
                          final liveSongs = customMap[playlistName] ?? [];
                          final liveSongIds = liveSongs.map((s) => s.id).toSet();
                          final invalidSelectedIds = selectedSongIds
                              .where((id) => !liveSongIds.contains(id))
                              .toList();
                          if (invalidSelectedIds.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              setModalState(() {
                                selectedSongIds.removeAll(invalidSelectedIds);
                              });
                            });
                          }

                          if (liveSongs.isEmpty) {
                            return const Center(
                              child: Text(
                                "Empty playlist. Tap '+' to add songs.",
                                style: TextStyle(color: Colors.white54),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: controller,
                            itemCount: liveSongs.length,
                            itemBuilder: (context, index) {
                              final song = liveSongs[index];
                              final isSelected = selectedSongIds.contains(song.id);
                              final isSongSelectionMode = selectedSongIds.isNotEmpty;
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                                leading: Icon(
                                  isSongSelectionMode
                                      ? (isSelected ? Icons.check_circle : Icons.circle_outlined)
                                      : Icons.music_note,
                                  color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white54,
                                ),
                                title: Text(song.title, style: const TextStyle(color: Colors.white), maxLines: 1),
                                subtitle: Text(song.artist ?? 'Unknown', style: const TextStyle(color: Colors.white54)),
                                onLongPress: () {
                                  setModalState(() {
                                    if (isSelected) {
                                      selectedSongIds.remove(song.id);
                                    } else {
                                      selectedSongIds.add(song.id);
                                    }
                                  });
                                },
                                onTap: () {
                                  if (isSongSelectionMode) {
                                    setModalState(() {
                                      if (isSelected) {
                                        selectedSongIds.remove(song.id);
                                      } else {
                                        selectedSongIds.add(song.id);
                                      }
                                    });
                                  } else {
                                    Navigator.pop(context);
                                    unawaited(
                                      widget.onPlaySong(
                                        song,
                                        queue: List<SongModel>.from(liveSongs),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSongsToPlaylist(String playlistName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.94,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => AddSongsToPlaylistSheet(
          playlistName: playlistName,
          allSongs: widget.allSongs,
          scrollController: controller,
          onStatus: ({required message, required icon, required color}) {
            _showTopStatus(message: message, icon: icon, color: color);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          setState(() => _selectedPlaylists.clear());
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedPlaylists.clear()),
                )
              : const BackButton(),
          title: Text(
            _isSelectionMode ? '${_selectedPlaylists.length} Selected' : 'Playlists',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: _deleteSelectedPlaylists,
              )
            else
              IconButton(icon: const Icon(Icons.add), onPressed: _showCreatePlaylistDialog),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<List<SongModel>>(
                      valueListenable: MusicState.favorites,
                      builder: (context, list, _) => PlaylistSquareCard(
                        title: 'Favorites',
                        songCount: list.length,
                        icon: Icons.favorite,
                        iconColor: Colors.pinkAccent,
                        onTap: () {
                          if (!_isSelectionMode) _showCustomPlaylistDetails('Favorites', list, isBuiltIn: true);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ValueListenableBuilder<List<SongModel>>(
                      valueListenable: MusicState.recentlyPlayed,
                      builder: (context, list, _) => PlaylistSquareCard(
                        title: 'Recently Played',
                        songCount: list.length,
                        icon: Icons.history,
                        iconColor: Colors.blueAccent,
                        onTap: () {
                          if (!_isSelectionMode) {
                            _showCustomPlaylistDetails('Recently Played', list, isBuiltIn: true);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ValueListenableBuilder<Map<String, List<SongModel>>>(
                valueListenable: MusicState.customPlaylists,
                builder: (context, customMap, _) {
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Playlist (${customMap.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (customMap.isEmpty)
                          const Text(
                            'Click the + button above to create a playlist.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        Expanded(
                          child: ListView(
                            children: customMap.entries.map((entry) {
                              final isSelected = _selectedPlaylists.contains(entry.key);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                selected: isSelected,
                                selectedTileColor: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                leading: Container(
                                  height: 50,
                                  width: 50,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.queue_music, color: Theme.of(context).colorScheme.secondary),
                                ),
                                title: Text(
                                  entry.key,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('${entry.value.length} songs', style: const TextStyle(color: Colors.white54)),
                                trailing: _isSelectionMode
                                    ? Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white54,
                                      )
                                    : const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                                onLongPress: () {
                                  if (!_isSelectionMode) _toggleSelection(entry.key);
                                },
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _toggleSelection(entry.key);
                                  } else {
                                    _showCustomPlaylistDetails(entry.key, entry.value);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        bottomSheet: widget.currentSongNotifier.value == null
            ? null
            : MiniPlayer(
                currentSong: widget.currentSongNotifier.value!,
                isPlaying: widget.audioPlayer.playing,
                onPlayPause: widget.onPlayPause,
                onNext: widget.onNext,
                onPrevious: widget.onPrevious,
                onTap: widget.onOpenFullPlayer,
              ),
      ),
    );
  }

}
