import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/music_state.dart';
import '../widgets/mini_player.dart';
import '../widgets/playing_indicator.dart';
import 'library/app_about_sheet.dart';
import 'full_player_screen.dart';
import 'playlist_screen.dart';
import 'song_downloader_screen.dart';

enum LibrarySortMode { titleAz, titleZa, newestFirst, oldestFirst, artistAz }

class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key});

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen> {
  static const String _sortModePrefKey = 'library_sort_mode_v1';
  static const int _searchMaxVisibleItems = 5;

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<SongModel> _allSongs = [];
  List<SongModel> _filteredSongs = [];
  List<SongModel> _searchMatches = const [];
  List<SongModel> _activeQueueSongs = [];
  String _activeQueueSignature = '';
  ConcatenatingAudioSource? _queueSource;

  SongModel? _currentSong;
  final ValueNotifier<SongModel?> _currentSongNotifier = ValueNotifier(null);

  bool _isPlaying = false;
  bool _hasPermission = false;
  bool _isLibraryLoading = true;
  bool _showInlineSearch = false;
  String _searchQuery = '';
  LibrarySortMode _sortMode = LibrarySortMode.titleAz;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<AudioInterruptionEvent>? _audioInterruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  AudioSession? _audioSession;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeLibrary());
    unawaited(_configureAudioSession());
    unawaited(_audioPlayer.setLoopMode(LoopMode.all));

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
    _currentIndexSubscription = _audioPlayer.currentIndexStream.listen((index) {
      if (index == null ||
          index < 0 ||
          index >= _activeQueueSongs.length ||
          !mounted) {
        return;
      }
      final song = _activeQueueSongs[index];
      if (_currentSong?.id == song.id) {
        return;
      }
      setState(() => _currentSong = song);
      _currentSongNotifier.value = song;
      MusicState.addRecent(song);
    });
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _audioInterruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _audioPlayer.dispose();
    _currentSongNotifier.dispose();
    super.dispose();
  }

  Future<void> _initializeLibrary() async {
    await _loadSavedSortMode();
    if (!mounted) return;
    await _requestPermissionAndFetchSongs();
  }

  Future<void> _loadSavedSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_sortModePrefKey);
    if (savedIndex == null) return;
    if (savedIndex < 0 || savedIndex >= LibrarySortMode.values.length) return;

    final mode = LibrarySortMode.values[savedIndex];
    if (!mounted) {
      _sortMode = mode;
      return;
    }
    setState(() => _sortMode = mode);
  }

  Future<void> _persistSortMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sortModePrefKey, _sortMode.index);
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _audioSession = session;

      _becomingNoisySub?.cancel();
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (_audioPlayer.playing) {
          unawaited(_audioPlayer.pause());
        }
      });

      _audioInterruptionSub?.cancel();
      _audioInterruptionSub = session.interruptionEventStream.listen((event) {
        if (!event.begin) return;
        if (event.type == AudioInterruptionType.pause ||
            event.type == AudioInterruptionType.duck) {
          unawaited(_audioPlayer.pause());
        }
      });
    } catch (_) {
      // Best effort; playback still works without explicit session setup.
    }
  }

  Future<void> _activateAudioSession() async {
    try {
      await _audioSession?.setActive(true);
    } catch (_) {
      // Ignore activation errors and continue attempting playback.
    }
  }

  Future<void> _requestPermissionAndFetchSongs() async {
    await _requestNotificationPermission();
    final permissionStatus = await _requestMediaPermission();
    if (!mounted) return;
    if (permissionStatus) {
      setState(() => _hasPermission = true);
      await _fetchSongs();
    } else {
      setState(() => _hasPermission = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<bool> _requestMediaPermission() async {
    if (await Permission.audio.isGranted ||
        await Permission.storage.isGranted) {
      return true;
    }

    final statuses = await [Permission.audio, Permission.storage].request();
    final audioGranted = statuses[Permission.audio]?.isGranted ?? false;
    final storageGranted = statuses[Permission.storage]?.isGranted ?? false;
    return audioGranted || storageGranted;
  }

  bool _isSupportedSong(SongModel song) {
    final path = song.data.trim().toLowerCase();
    return song.uri != null && path.endsWith('.mp3');
  }

  Future<void> _fetchSongs() async {
    setState(() => _isLibraryLoading = true);
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (!mounted) return;

      final supportedSongs = songs.where(_isSupportedSong).toList();
      final sortedSongs = _applySort(supportedSongs);
      setState(() {
        _allSongs = supportedSongs;
        _filteredSongs = sortedSongs;
        _isLibraryLoading = false;
      });
      _refreshSearchMatches();

      if (_audioPlayer.audioSource == null || _activeQueueSongs.isEmpty) {
        _activeQueueSongs = List<SongModel>.from(sortedSongs);
        _activeQueueSignature = '';
        _queueSource = null;
      }
      await MusicState.init(supportedSongs);
    } on Exception catch (e) {
      debugPrint('Error loading songs: $e');
      if (!mounted) return;
      setState(() => _isLibraryLoading = false);
    }
  }

  List<SongModel> _findSearchMatches(String query) {
    return _filteredSongs
        .where((song) {
          final title = song.title.toLowerCase();
          final artist = (song.artist ?? '').toLowerCase();
          return title.contains(query) || artist.contains(query);
        })
        .toList(growable: false);
  }

  void _refreshSearchMatches() {
    final normalized = _searchQuery.trim().toLowerCase();
    final matches = normalized.isEmpty
        ? const <SongModel>[]
        : _findSearchMatches(normalized);
    if (!mounted) {
      _searchMatches = matches;
      return;
    }
    setState(() => _searchMatches = matches);
  }

  void _toggleInlineSearch() {
    if (!_showInlineSearch) {
      setState(() => _showInlineSearch = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeInlineSearch() {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _showInlineSearch = false;
      _searchQuery = '';
      _searchMatches = const [];
      _searchController.clear();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 90), () {
      if (!mounted) return;
      final normalized = value.trim().toLowerCase();
      setState(() {
        _searchQuery = normalized;
        _searchMatches = normalized.isEmpty
            ? const []
            : _findSearchMatches(normalized);
      });
    });
  }

  Future<void> _playSongFromSearch(SongModel song) async {
    await _playSong(song, queue: _filteredSongs);
    if (!mounted) return;
    _closeInlineSearch();
  }

  String _normalizeSortText(String value) => value.trim().toLowerCase();

  int _songDateAdded(SongModel song) => song.dateAdded ?? 0;

  List<SongModel> _applySort(List<SongModel> songs) {
    final sorted = List<SongModel>.from(songs);
    sorted.sort((a, b) {
      switch (_sortMode) {
        case LibrarySortMode.titleAz:
          return _normalizeSortText(
            a.title,
          ).compareTo(_normalizeSortText(b.title));
        case LibrarySortMode.titleZa:
          return _normalizeSortText(
            b.title,
          ).compareTo(_normalizeSortText(a.title));
        case LibrarySortMode.newestFirst:
          return _songDateAdded(b).compareTo(_songDateAdded(a));
        case LibrarySortMode.oldestFirst:
          return _songDateAdded(a).compareTo(_songDateAdded(b));
        case LibrarySortMode.artistAz:
          final artistA = _normalizeSortText(a.artist ?? '');
          final artistB = _normalizeSortText(b.artist ?? '');
          final artistCompare = artistA.compareTo(artistB);
          if (artistCompare != 0) return artistCompare;
          return _normalizeSortText(
            a.title,
          ).compareTo(_normalizeSortText(b.title));
      }
    });
    return sorted;
  }

  String _sortShortLabel(LibrarySortMode mode) {
    switch (mode) {
      case LibrarySortMode.titleAz:
        return 'A-Z';
      case LibrarySortMode.titleZa:
        return 'Z-A';
      case LibrarySortMode.newestFirst:
        return 'New';
      case LibrarySortMode.oldestFirst:
        return 'Old';
      case LibrarySortMode.artistAz:
        return 'Art';
    }
  }

  String _sortMenuLabel(LibrarySortMode mode) {
    switch (mode) {
      case LibrarySortMode.titleAz:
        return 'Title A to Z';
      case LibrarySortMode.titleZa:
        return 'Title Z to A';
      case LibrarySortMode.newestFirst:
        return 'Newest first';
      case LibrarySortMode.oldestFirst:
        return 'Oldest first';
      case LibrarySortMode.artistAz:
        return 'Artist A to Z';
    }
  }

  void _setSortMode(LibrarySortMode mode) {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
      _filteredSongs = _applySort(_allSongs);
    });
    _refreshSearchMatches();
    unawaited(_persistSortMode());
  }

  void _showPlaybackError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
      );
  }

  MediaItem _buildMediaItem(SongModel song) {
    final artworkUri = song.albumId == null
        ? null
        : Uri.parse('content://media/external/audio/albumart/${song.albumId}');
    return MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown Artist',
      album: song.album,
      artUri: artworkUri,
    );
  }

  String _buildQueueSignature(List<SongModel> queueSongs) =>
      queueSongs.map((song) => song.id).join(',');

  Future<void> _ensureQueueReady({
    required List<SongModel> queueSongs,
    required int initialIndex,
  }) async {
    if (queueSongs.isEmpty) return;
    final queueSignature = _buildQueueSignature(queueSongs);
    final shouldRebuildQueue =
        _queueSource == null ||
        _activeQueueSignature != queueSignature ||
        _queueSource!.children.length != queueSongs.length ||
        !identical(_audioPlayer.audioSource, _queueSource);

    if (shouldRebuildQueue) {
      _queueSource = ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: queueSongs
            .map(
              (song) => AudioSource.uri(
                Uri.parse(song.uri!),
                tag: _buildMediaItem(song),
              ),
            )
            .toList(),
      );
      _activeQueueSongs = List<SongModel>.from(queueSongs);
      _activeQueueSignature = queueSignature;
      await _audioPlayer.setAudioSource(
        _queueSource!,
        initialIndex: initialIndex,
        initialPosition: Duration.zero,
      );
      return;
    }

    _activeQueueSongs = List<SongModel>.from(queueSongs);
    await _audioPlayer.seek(Duration.zero, index: initialIndex);
  }

  Future<void> _playSong(SongModel song, {List<SongModel>? queue}) async {
    try {
      final candidateQueue = (queue ?? _allSongs)
          .where(_isSupportedSong)
          .toList();
      if (candidateQueue.isEmpty) {
        _showPlaybackError('No supported MP3 songs found to play.');
        return;
      }

      final index = candidateQueue.indexWhere((item) => item.id == song.id);
      if (index < 0) {
        _showPlaybackError('Selected song is not available in this playlist.');
        return;
      }

      final playableSong = candidateQueue[index];
      await _ensureQueueReady(queueSongs: candidateQueue, initialIndex: index);

      setState(() => _currentSong = playableSong);
      _currentSongNotifier.value = playableSong;
      await _activateAudioSession();
      await _audioPlayer.play();
    } on Exception catch (e) {
      debugPrint('Error playing song: $e');
      _showPlaybackError('Could not play this song. Please try another MP3.');
    }
  }

  void _togglePlayPause() {
    if (_audioPlayer.audioSource == null && _currentSong != null) {
      unawaited(
        _playSong(
          _currentSong!,
          queue: _activeQueueSongs.isEmpty ? _filteredSongs : _activeQueueSongs,
        ),
      );
      return;
    }
    if (_isPlaying) {
      unawaited(_audioPlayer.pause());
      return;
    }
    unawaited(_resumePlayback());
  }

  Future<void> _resumePlayback() async {
    await _activateAudioSession();
    await _audioPlayer.play();
  }

  void _playNext() async {
    if (_activeQueueSongs.isEmpty) return;
    if (_audioPlayer.audioSource == null) {
      await _playSong(_activeQueueSongs.first, queue: _activeQueueSongs);
      return;
    }
    if (_audioPlayer.hasNext) {
      await _audioPlayer.seekToNext();
    } else {
      await _audioPlayer.seek(Duration.zero, index: 0);
    }
    if (!_audioPlayer.playing) await _resumePlayback();
  }

  void _playPrevious() async {
    if (_activeQueueSongs.isEmpty) return;
    if (_audioPlayer.audioSource == null) {
      await _playSong(_activeQueueSongs.first, queue: _activeQueueSongs);
      return;
    }
    if (_audioPlayer.hasPrevious) {
      await _audioPlayer.seekToPrevious();
    } else {
      await _audioPlayer.seek(
        Duration.zero,
        index: _activeQueueSongs.length - 1,
      );
    }
    if (!_audioPlayer.playing) await _resumePlayback();
  }

  void _openFullPlayer() {
    if (_currentSong == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) => MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: FullPlayerScreen(
            audioPlayer: _audioPlayer,
            currentSongNotifier: _currentSongNotifier,
            onNext: _playNext,
            onPrevious: _playPrevious,
          ),
        ),
      ),
    );
  }

  void _openAboutFromDrawer() {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      showAppAboutSheet(context);
    });
  }

  Future<void> _refreshLibraryAfterDownload() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _fetchSongs();
  }

  Widget _buildSongArtwork({
    required SongModel song,
    required ThemeData theme,
    required bool isActive,
  }) {
    return QueryArtworkWidget(
      controller: _audioQuery,
      id: song.id,
      type: ArtworkType.AUDIO,
      format: ArtworkFormat.JPEG,
      quality: 70,
      size: 200,
      keepOldArtwork: true,
      artworkQuality: FilterQuality.low,
      artworkHeight: 45,
      artworkWidth: 45,
      artworkFit: BoxFit.cover,
      artworkBorder: BorderRadius.circular(8),
      nullArtworkWidget: Container(
        height: 45,
        width: 45,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.music_note,
          color: isActive ? theme.colorScheme.secondary : Colors.white54,
        ),
      ),
    );
  }

  Widget _buildInlineSearch(ThemeData theme) {
    final dropdownMaxHeight = 64.0 * _searchMaxVisibleItems;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search songs by title or artist...',
            hintStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: theme.colorScheme.surface,
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.secondary,
            ),
            suffixIcon: IconButton(
              tooltip: 'Close search',
              onPressed: _closeInlineSearch,
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_searchQuery.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(maxHeight: dropdownMaxHeight),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.cardColor),
            ),
            child: _searchMatches.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    child: Text(
                      'No songs found',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _searchMatches.length,
                    itemBuilder: (context, index) {
                      final song = _searchMatches[index];
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -1),
                        leading: _buildSongArtwork(
                          song: song,
                          theme: theme,
                          isActive: _currentSong?.id == song.id,
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          song.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        onTap: () => unawaited(_playSongFromSearch(song)),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.56,
        backgroundColor: theme.colorScheme.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.secondary),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.music_note, color: Colors.white, size: 50),
                  SizedBox(height: 10),
                  Text(
                    'Z Music',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.library_music, color: Colors.white),
              title: const Text(
                'Library',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play, color: Colors.white),
              title: const Text(
                'Playlists',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlaylistScreen(
                      onPlaySong: _playSong,
                      allSongs: _allSongs,
                      audioPlayer: _audioPlayer,
                      currentSongNotifier: _currentSongNotifier,
                      onPlayPause: _togglePlayPause,
                      onNext: _playNext,
                      onPrevious: _playPrevious,
                      onOpenFullPlayer: _openFullPlayer,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.download_for_offline_rounded,
                color: Colors.white,
              ),
              title: const Text(
                'Download Songs',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SongDownloaderScreen(
                      audioPlayer: _audioPlayer,
                      currentSongNotifier: _currentSongNotifier,
                      onPlayPause: _togglePlayPause,
                      onNext: _playNext,
                      onPrevious: _playPrevious,
                      onOpenFullPlayer: _openFullPlayer,
                      onDownloadCompleted: () {
                        unawaited(_refreshLibraryAfterDownload());
                      },
                    ),
                  ),
                ).then((_) => unawaited(_fetchSongs()));
              },
            ),
            const Divider(
              color: Colors.white24,
              height: 22,
              indent: 14,
              endIndent: 14,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text(
                'About',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              subtitle: const Text(
                'Developer & app details',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: _openAboutFromDrawer,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(color: theme.cardColor.withValues(alpha: 0.4)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white, size: 24),
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Library',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color: theme.colorScheme.secondary,
                            size: 26,
                          ),
                          onPressed: _toggleInlineSearch,
                        ),
                        PopupMenuButton<LibrarySortMode>(
                          tooltip: 'Sort songs',
                          initialValue: _sortMode,
                          onSelected: _setSortMode,
                          color: theme.colorScheme.surface,
                          itemBuilder: (context) => LibrarySortMode.values
                              .map(
                                (mode) => PopupMenuItem<LibrarySortMode>(
                                  value: mode,
                                  child: Text(
                                    _sortMenuLabel(mode),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: theme.cardColor),
                            ),
                            child: Text(
                              _sortShortLabel(_sortMode),
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showInlineSearch) ...[
                      const SizedBox(height: 10),
                      _buildInlineSearch(theme),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: !_hasPermission
                  ? const Center(
                      child: Text('Waiting for storage permission...'),
                    )
                  : _isLibraryLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.secondary,
                      ),
                    )
                  : _allSongs.isEmpty
                  ? const Center(
                      child: Text(
                        'No MP3 songs found on your device.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredSongs.length,
                      padding: const EdgeInsets.only(bottom: 90),
                      itemBuilder: (context, index) {
                        final song = _filteredSongs[index];
                        final isActive = _currentSong?.id == song.id;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          tileColor: isActive
                              ? theme.colorScheme.surface.withValues(
                                  alpha: 0.55,
                                )
                              : Colors.transparent,
                          leading: _buildSongArtwork(
                            song: song,
                            theme: theme,
                            isActive: isActive,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? theme.colorScheme.secondary
                                  : Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            song.artist ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: isActive && _isPlaying
                              ? PlayingIndicator(
                                  color: theme.colorScheme.secondary,
                                )
                              : null,
                          onTap: () => _playSong(song, queue: _filteredSongs),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomSheet: _currentSong == null
          ? null
          : MiniPlayer(
              currentSong: _currentSong!,
              isPlaying: _isPlaying,
              onPlayPause: _togglePlayPause,
              onNext: _playNext,
              onPrevious: _playPrevious,
              onTap: _openFullPlayer,
            ),
    );
  }
}

