import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum YouTubeInputType { videoId, link, search }

class YouTubeInputResolution {
  final String videoId;
  final YouTubeInputType inputType;
  final String originalInput;

  const YouTubeInputResolution({
    required this.videoId,
    required this.inputType,
    required this.originalInput,
  });

  String get inputTypeLabel {
    switch (inputType) {
      case YouTubeInputType.videoId:
        return 'Video ID';
      case YouTubeInputType.link:
        return 'YouTube Link';
      case YouTubeInputType.search:
        return 'Song Search';
    }
  }
}

class YouTubeHelper {
  static final RegExp _idRegExp = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static final RegExp _fallbackIdExtractor = RegExp(
    r'(?:v=|\/)([a-zA-Z0-9_-]{11})(?:[?&]|$)',
  );

  static Future<YouTubeInputResolution?> resolveInput(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    final extractedId = _extractId(input);
    if (extractedId != null) {
      return YouTubeInputResolution(
        videoId: extractedId,
        inputType: _idRegExp.hasMatch(input)
            ? YouTubeInputType.videoId
            : YouTubeInputType.link,
        originalInput: rawInput,
      );
    }

    final searchedId = await _searchTopVideoId(input);
    if (searchedId == null) return null;

    return YouTubeInputResolution(
      videoId: searchedId,
      inputType: YouTubeInputType.search,
      originalInput: rawInput,
    );
  }

  static String? _extractId(String input) {
    if (_idRegExp.hasMatch(input)) return input;

    final uri = Uri.tryParse(input);
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host
          .toLowerCase()
          .replaceFirst('www.', '')
          .replaceFirst('m.', '');

      if (host == 'youtu.be') {
        if (uri.pathSegments.isNotEmpty) {
          final firstSegment = uri.pathSegments.first;
          if (_idRegExp.hasMatch(firstSegment)) return firstSegment;
        }
      }

      if (host.endsWith('youtube.com')) {
        final queryId = uri.queryParameters['v'];
        if (queryId != null && _idRegExp.hasMatch(queryId)) return queryId;

        if (uri.pathSegments.length >= 2) {
          final section = uri.pathSegments.first.toLowerCase();
          final candidate = uri.pathSegments[1];
          if ((section == 'shorts' || section == 'embed') &&
              _idRegExp.hasMatch(candidate)) {
            return candidate;
          }
        }
      }
    }

    final fallbackMatch = _fallbackIdExtractor.firstMatch(input);
    return fallbackMatch?.group(1);
  }

  static Future<String?> _searchTopVideoId(String query) async {
    final yt = YoutubeExplode();
    try {
      final results = await yt.search.search(query);
      for (final result in results) {
        final id = result.id.value;
        if (_idRegExp.hasMatch(id)) return id;
      }
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
    return null;
  }
}
