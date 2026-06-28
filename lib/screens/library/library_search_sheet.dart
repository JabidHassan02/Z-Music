import 'dart:async';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

Future<SongModel?> showLibrarySearchSheet({
  required BuildContext context,
  required List<SongModel> songs,
}) {
  return showModalBottomSheet<SongModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _LibrarySearchSheet(songs: songs),
  );
}

class _LibrarySearchSheet extends StatefulWidget {
  final List<SongModel> songs;

  const _LibrarySearchSheet({required this.songs});

  @override
  State<_LibrarySearchSheet> createState() => _LibrarySearchSheetState();
}

class _LibrarySearchSheetState extends State<_LibrarySearchSheet> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Timer? _debounce;
  List<SongModel> _matches = const [];
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _activeQuery) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;

      final filteredSongs = normalized.isEmpty
          ? const <SongModel>[]
          : widget.songs
                .where((song) {
                  final title = song.title.toLowerCase();
                  final artist = (song.artist ?? '').toLowerCase();
                  return title.contains(normalized) ||
                      artist.contains(normalized);
                })
                .toList(growable: false);

      setState(() {
        _activeQuery = normalized;
        _matches = filteredSongs;
      });
    });
  }

  Widget _buildArtworkFallback(ThemeData theme) {
    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note, color: Colors.white70),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.68,
          child: Column(
            children: [
              Container(
                width: 50,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              TextField(
                controller: _queryController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search tracks...',
                  hintStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.search, color: Colors.white60),
                  filled: true,
                  fillColor: theme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _activeQuery.isEmpty
                    ? const Center(
                        child: Text(
                          'Start typing to search songs',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : _matches.isEmpty
                    ? const Center(
                        child: Text(
                          'No songs found',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: _matches.length,
                        itemBuilder: (context, index) {
                          final song = _matches[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            leading: QueryArtworkWidget(
                              controller: _audioQuery,
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              format: ArtworkFormat.JPEG,
                              quality: 60,
                              size: 160,
                              keepOldArtwork: true,
                              artworkQuality: FilterQuality.low,
                              artworkHeight: 42,
                              artworkWidth: 42,
                              artworkBorder: BorderRadius.circular(8),
                              nullArtworkWidget: _buildArtworkFallback(theme),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              song.artist ?? 'Unknown Artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                            onTap: () => Navigator.pop(context, song),
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
}
