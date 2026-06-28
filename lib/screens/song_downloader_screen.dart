import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/download_access_key_store.dart';
import '../services/youtube_api_service.dart';
import '../services/youtube_helper.dart';
import '../widgets/mini_player.dart';

class SongDownloaderScreen extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final ValueNotifier<SongModel?> currentSongNotifier;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onOpenFullPlayer;
  final VoidCallback onDownloadCompleted;

  const SongDownloaderScreen({
    super.key,
    required this.audioPlayer,
    required this.currentSongNotifier,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onOpenFullPlayer,
    required this.onDownloadCompleted,
  });

  @override
  State<SongDownloaderScreen> createState() => _SongDownloaderScreenState();
}

class _SongDownloaderScreenState extends State<SongDownloaderScreen> {
  static const MethodChannel _downloadChannel = MethodChannel(
    'com.example.music_app/downloader',
  );

  final TextEditingController _inputController = TextEditingController();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  StreamSubscription<PlayerState>? _playerStateSub;

  bool _isLoading = false;
  bool _isDownloading = false;
  bool _isPlaying = false;
  bool _isLibraryCacheLoaded = false;
  String? _errorMessage;
  YouTubeInputResolution? _resolvedInput;
  YouTubeDownloadResult? _downloadResult;
  SongModel? _existingSongMatch;
  List<SongModel> _libraryMp3Songs = const [];
  final Set<String> _sessionDownloadedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.audioPlayer.playing;
    unawaited(_loadLibraryCache());
    widget.currentSongNotifier.addListener(_refreshMiniPlayer);
    _playerStateSub = widget.audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    widget.currentSongNotifier.removeListener(_refreshMiniPlayer);
    _inputController.dispose();
    super.dispose();
  }

  void _refreshMiniPlayer() {
    if (mounted) setState(() {});
  }

  bool _isSupportedMp3(SongModel song) {
    final path = song.data.trim().toLowerCase();
    return song.uri != null && path.endsWith('.mp3');
  }

  String _normalizeExactKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Set<String> _buildLookupCandidates({
    required String rawInput,
    String? resolvedTitle,
  }) {
    return <String>{
      _normalizeExactKey(rawInput),
      if (resolvedTitle != null) _normalizeExactKey(resolvedTitle),
    }..removeWhere((item) => item.isEmpty);
  }

  Set<String> _buildSessionCandidates({
    required String rawInput,
    String? resolvedTitle,
    String? videoId,
  }) {
    return <String>{
      ..._buildLookupCandidates(
        rawInput: rawInput,
        resolvedTitle: resolvedTitle,
      ),
      if (videoId != null) _normalizeExactKey(videoId),
    }..removeWhere((item) => item.isEmpty);
  }

  bool _wasDownloadedInSession({
    required String rawInput,
    String? resolvedTitle,
    String? videoId,
  }) {
    final candidates = _buildSessionCandidates(
      rawInput: rawInput,
      resolvedTitle: resolvedTitle,
      videoId: videoId,
    );
    return candidates.any(_sessionDownloadedKeys.contains);
  }

  void _rememberDownloadedInSession({
    required String rawInput,
    String? resolvedTitle,
    String? videoId,
  }) {
    _sessionDownloadedKeys.addAll(
      _buildSessionCandidates(
        rawInput: rawInput,
        resolvedTitle: resolvedTitle,
        videoId: videoId,
      ),
    );
  }

  Future<void> _loadLibraryCache() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (!mounted) return;
      _libraryMp3Songs = songs.where(_isSupportedMp3).toList(growable: false);
      _isLibraryCacheLoaded = true;
    } catch (_) {
      _isLibraryCacheLoaded = true;
      _libraryMp3Songs = const [];
    }
  }

  Future<SongModel?> _findExistingSongMatch({
    required String rawInput,
    String? resolvedTitle,
  }) async {
    if (!_isLibraryCacheLoaded) {
      await _loadLibraryCache();
    }

    final candidates = _buildLookupCandidates(
      rawInput: rawInput,
      resolvedTitle: resolvedTitle,
    );
    if (candidates.isEmpty) return null;

    for (final song in _libraryMp3Songs) {
      final songKey = _normalizeExactKey(song.title);
      if (candidates.contains(songKey)) {
        return song;
      }
    }
    return null;
  }

  Future<void> _pasteFromClipboard() async {
    final content = await Clipboard.getData(Clipboard.kTextPlain);
    final text = content?.text?.trim();
    if (!mounted) return;

    if (text == null || text.isEmpty) {
      _showStatus('Clipboard is empty.', isError: true);
      return;
    }

    setState(() => _inputController.text = text);
    await _handleSmartDownload();
  }

  Future<void> _openAccessKeySheet() async {
    final hasStoredKey = (await DownloadAccessKeyStore.read()) != null;
    if (!mounted) return;

    final resultMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AccessKeySheet(hasStoredKey: hasStoredKey),
    );

    if (!mounted || resultMessage == null) return;
    _showStatus(resultMessage);
  }

  Future<void> _handleSmartDownload() async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty) {
      _showStatus(
        'Enter a YouTube link, video ID, or song name.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resolvedInput = null;
      _downloadResult = null;
      _existingSongMatch = null;
    });

    final resolved = await YouTubeHelper.resolveInput(raw);
    if (!mounted) return;

    if (resolved == null) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Smart Helper could not find a valid YouTube match for "$raw".';
      });
      return;
    }

    final downloadResult = await YouTubeApiService.getMp3DownloadLink(
      resolved.videoId,
    );
    if (!mounted) return;

    SongModel? existingSong;
    var isSessionDuplicate = false;
    if (downloadResult.isSuccess) {
      existingSong = await _findExistingSongMatch(
        rawInput: raw,
        resolvedTitle: downloadResult.title,
      );
      if (!mounted) return;
      isSessionDuplicate = _wasDownloadedInSession(
        rawInput: raw,
        resolvedTitle: downloadResult.title,
        videoId: resolved.videoId,
      );
    }

    setState(() {
      _isLoading = false;
      _resolvedInput = resolved;
      _existingSongMatch = existingSong;
      _downloadResult =
          downloadResult.isSuccess &&
              existingSong == null &&
              !isSessionDuplicate
          ? downloadResult
          : null;
      _errorMessage = downloadResult.isSuccess ? null : downloadResult.message;
    });

    if (existingSong != null) {
      _showStatus('Already available in library: ${existingSong.title}');
    } else if (isSessionDuplicate) {
      _showStatus('This song was already downloaded in this session.');
    }
  }

  Future<SongModel?> _refreshAndFindMatch({
    required String rawInput,
    String? resolvedTitle,
  }) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await _loadLibraryCache();
      final match = await _findExistingSongMatch(
        rawInput: rawInput,
        resolvedTitle: resolvedTitle,
      );
      if (match != null) return match;
      await Future.delayed(const Duration(milliseconds: 450));
    }
    return null;
  }

  Future<void> _downloadSongToDevice() async {
    final result = _downloadResult;
    final link = result?.downloadUrl;
    if (result == null || link == null || link.isEmpty) {
      _showStatus('No download link available.', isError: true);
      return;
    }

    setState(() => _isDownloading = true);
    try {
      await _downloadChannel.invokeMethod<String>('downloadMp3', {
        'url': link,
        'title': (result.title ?? _resolvedInput?.videoId ?? 'song').trim(),
      });
      if (!mounted) return;

      final rawInput = _inputController.text.trim();
      _rememberDownloadedInSession(
        rawInput: rawInput,
        resolvedTitle: result.title,
        videoId: _resolvedInput?.videoId,
      );
      final match = await _refreshAndFindMatch(
        rawInput: rawInput,
        resolvedTitle: result.title,
      );
      if (!mounted) return;

      setState(() {
        _existingSongMatch = match ?? _existingSongMatch;
        _downloadResult = null;
      });

      _showStatus('Song downloaded to Music/Z Music');
      widget.onDownloadCompleted();
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showStatus(
        e.message ?? 'Failed to download song to device.',
        isError: true,
      );
    } on MissingPluginException {
      if (!mounted) return;
      _showStatus(
        'Downloader is not initialized. Fully restart the app once.',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      _showStatus('Failed to download song to device.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _copyDownloadLink() async {
    final link = _downloadResult?.downloadUrl;
    if (link == null || link.isEmpty) {
      _showStatus('No download link available.', isError: true);
      return;
    }

    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _showStatus('Download link copied.');
  }

  void _showStatus(String message, {bool isError = false}) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Colors.redAccent
          : Theme.of(context).colorScheme.surface,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  String _formatDuration(int? totalSeconds) {
    if (totalSeconds == null || totalSeconds <= 0) return 'Unknown';
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.cardColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_download_rounded,
                color: theme.colorScheme.secondary,
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text(
                'Smart Song Downloader',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Paste a YouTube link, type a video ID, or write a song name. Smart Helper checks YouTube and your local library before giving an MP3 link.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.cardColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search Or Paste',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inputController,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _handleSmartDownload(),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.cardColor.withValues(alpha: 0.82),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: theme.colorScheme.secondary,
              ),
              suffixIcon: IconButton(
                onPressed: _pasteFromClipboard,
                icon: Icon(
                  Icons.content_paste_rounded,
                  color: theme.colorScheme.secondary,
                ),
                tooltip: 'Paste',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleSmartDownload,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(_isLoading ? 'Resolving...' : 'Find & Download MP3'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: theme.cardColor,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Smart Helper is finding the best match and requesting MP3 link...',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, YouTubeDownloadResult result) {
    final resolved = _resolvedInput;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: theme.colorScheme.secondary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'MP3 Link Ready',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.title?.trim().isNotEmpty == true
                ? result.title!
                : 'Unknown title',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'Duration: ${_formatDuration(result.durationSeconds)}',
            style: const TextStyle(color: Colors.white70),
          ),
          if (resolved != null) ...[
            const SizedBox(height: 4),
            Text(
              'Matched using: ${resolved.inputTypeLabel}',
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Video ID: ${resolved.videoId}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadSongToDevice,
              icon: const Icon(Icons.download_for_offline_rounded),
              label: Text(_isDownloading ? 'Downloading...' : 'Download MP3'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: theme.cardColor,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _copyDownloadLink,
              icon: Icon(
                Icons.copy_rounded,
                color: theme.colorScheme.secondary,
              ),
              label: const Text('Copy Download Link'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme.cardColor),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                foregroundColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyAvailableCard(ThemeData theme, SongModel song) {
    final resolved = _resolvedInput;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.library_music_rounded,
                color: theme.colorScheme.secondary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Already In Library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            song.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            song.artist ?? 'Unknown Artist',
            style: const TextStyle(color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (resolved != null) ...[
            const SizedBox(height: 8),
            Text(
              'Matched using: ${resolved.inputTypeLabel}',
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'This exact song is already available on your device.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentSong = widget.currentSongNotifier.value;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Download Songs'),
        actions: [
          IconButton(
            onPressed: _openAccessKeySheet,
            icon: const Icon(Icons.key_rounded),
            tooltip: 'Access key',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.scaffoldBackgroundColor,
              theme.colorScheme.surface.withValues(alpha: 0.88),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _buildHeaderCard(theme),
            const SizedBox(height: 14),
            _buildInputCard(theme),
            const SizedBox(height: 14),
            if (_isLoading) _buildLoadingCard(theme),
            if (_errorMessage != null && !_isLoading) ...[
              _buildErrorCard(theme, _errorMessage!),
            ],
            if (_existingSongMatch != null && !_isLoading) ...[
              _buildAlreadyAvailableCard(theme, _existingSongMatch!),
            ],
            if (_downloadResult != null &&
                _downloadResult!.isSuccess &&
                !_isLoading) ...[
              _buildResultCard(theme, _downloadResult!),
            ],
          ],
        ),
      ),
      bottomSheet: currentSong == null
          ? null
          : MiniPlayer(
              currentSong: currentSong,
              isPlaying: _isPlaying,
              onPlayPause: widget.onPlayPause,
              onNext: widget.onNext,
              onPrevious: widget.onPrevious,
              onTap: widget.onOpenFullPlayer,
            ),
    );
  }
}

class _AccessKeySheet extends StatefulWidget {
  final bool hasStoredKey;

  const _AccessKeySheet({required this.hasStoredKey});

  @override
  State<_AccessKeySheet> createState() => _AccessKeySheetState();
}

class _AccessKeySheetState extends State<_AccessKeySheet> {
  late final TextEditingController _keyController;
  bool _obscureText = true;
  bool _isSaving = false;
  String? _operationError;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String get _keyText => _keyController.text.trim();

  int get _keyLength => _keyText.length;

  bool get _isValidLength =>
      _keyLength == DownloadAccessKeyStore.requiredLength;

  bool get _hasTypedKey => _keyText.isNotEmpty;

  bool get _canClear =>
      widget.hasStoredKey || _hasTypedKey;

  Future<void> _applyKey() async {
    if (!_isValidLength || _isSaving) return;
    setState(() {
      _isSaving = true;
      _operationError = null;
    });

    try {
      await DownloadAccessKeyStore.save(_keyText);
      if (!mounted) return;
      Navigator.pop(
        context,
        'Access key applied. It is now hidden on this device.',
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _operationError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _operationError = 'Could not save access key.';
      });
    }
  }

  Future<void> _clearKey() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _operationError = null;
    });

    try {
      await DownloadAccessKeyStore.clear();
      if (!mounted) return;
      Navigator.pop(context, 'Saved access key removed.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _operationError = 'Could not remove saved key.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validationError = _hasTypedKey && !_isValidLength
        ? 'Key must be exactly 50 characters.'
        : null;
    final errorText = _operationError ?? validationError;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              const Text(
                'Access Key',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter your 50-character access key to keep download service active.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 6),
          if (widget.hasStoredKey) ...[
            const Text(
              'A key is already applied and hidden for security. Enter a new key only if you want to replace it.',
              style: TextStyle(color: Colors.white60, height: 1.35),
            ),
            const SizedBox(height: 6),
          ],
          const Text(
            'If you do not have one, ask the owner for a valid key.',
            style: TextStyle(color: Colors.white60, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyController,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: _obscureText,
            maxLines: 1,
            onChanged: (_) {
              if (_operationError != null) {
                setState(() => _operationError = null);
              } else {
                setState(() {});
              }
            },
            decoration: InputDecoration(
              hintText: 'Paste access key',
              counterText:
                  '$_keyLength/${DownloadAccessKeyStore.requiredLength}',
              errorText: errorText,
              filled: true,
              fillColor: theme.cardColor.withValues(alpha: 0.8),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureText = !_obscureText),
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white70,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This key is stored securely on this device.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _canClear && !_isSaving ? _clearKey : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.cardColor),
                    foregroundColor: Colors.white70,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isValidLength && !_isSaving ? _applyKey : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_isSaving ? 'Saving...' : 'Apply'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: theme.cardColor,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
