import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../services/music_state.dart';

typedef PlaylistStatusCallback = void Function({
  required String message,
  required IconData icon,
  required Color color,
});

class AddSongsToPlaylistSheet extends StatelessWidget {
  final String playlistName;
  final List<SongModel> allSongs;
  final ScrollController scrollController;
  final PlaylistStatusCallback onStatus;

  const AddSongsToPlaylistSheet({
    super.key,
    required this.playlistName,
    required this.allSongs,
    required this.scrollController,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, List<SongModel>>>(
      valueListenable: MusicState.customPlaylists,
      builder: (context, customMap, _) {
        final currentPlaylistSongs = customMap[playlistName] ?? [];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    'Add to "$playlistName"',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currentPlaylistSongs.length} songs in this playlist',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: allSongs.length,
                itemBuilder: (context, index) {
                  final song = allSongs[index];
                  final isAdded = MusicState.isSongInCustomPlaylist(playlistName, song);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAdded
                          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      title: Text(song.title, style: const TextStyle(color: Colors.white), maxLines: 1),
                      subtitle: Text(
                        isAdded ? 'Already in playlist' : (song.artist ?? 'Unknown Artist'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isAdded ? Colors.white70 : Colors.white54),
                      ),
                      trailing: Icon(
                        isAdded ? Icons.check_circle : Icons.add_circle_outline_rounded,
                        color: isAdded ? Theme.of(context).colorScheme.secondary : Colors.white54,
                      ),
                      onTap: () {
                        final added = MusicState.addSongToCustomPlaylist(playlistName, song);
                        onStatus(
                          message: added
                              ? '"${song.title}" added to "$playlistName"'
                              : '"${song.title}" is already in "$playlistName"',
                          icon: added ? Icons.check_circle : Icons.info_outline_rounded,
                          color: added ? Theme.of(context).colorScheme.secondary : Colors.amberAccent,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
