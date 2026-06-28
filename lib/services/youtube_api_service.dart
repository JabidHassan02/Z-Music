import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'download_access_key_store.dart';

class YouTubeDownloadResult {
  final bool isSuccess;
  final String message;
  final String? downloadUrl;
  final String? title;
  final int? durationSeconds;

  const YouTubeDownloadResult._({
    required this.isSuccess,
    required this.message,
    this.downloadUrl,
    this.title,
    this.durationSeconds,
  });

  factory YouTubeDownloadResult.success({
    required String message,
    required String downloadUrl,
    String? title,
    int? durationSeconds,
  }) {
    return YouTubeDownloadResult._(
      isSuccess: true,
      message: message,
      downloadUrl: downloadUrl,
      title: title,
      durationSeconds: durationSeconds,
    );
  }

  factory YouTubeDownloadResult.failure(String message) {
    return YouTubeDownloadResult._(isSuccess: false, message: message);
  }
}

class YouTubeApiService {
  static const String _rapidHost = 'youtube-mp36.p.rapidapi.com';

  static Future<YouTubeDownloadResult> getMp3DownloadLink(
    String videoId,
  ) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) {
      return YouTubeDownloadResult.failure('Missing video ID.');
    }

    final apiKey = await _resolveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return YouTubeDownloadResult.failure('Access key is missing.');
    }

    final url = Uri.https(_rapidHost, '/dl', {'id': cleanId});
    try {
      final response = await http
          .get(
            url,
            headers: {'X-RapidAPI-Key': apiKey, 'X-RapidAPI-Host': _rapidHost},
          )
          .timeout(const Duration(seconds: 20));

      final decoded = _decodeJson(response.body);
      final status = decoded['status']?.toString().toLowerCase();
      final link = decoded['link']?.toString();
      final msg = decoded['msg']?.toString();

      if (response.statusCode == 200 &&
          status == 'ok' &&
          link != null &&
          link.isNotEmpty) {
        return YouTubeDownloadResult.success(
          message: 'Download link is ready.',
          downloadUrl: link,
          title: decoded['title']?.toString(),
          durationSeconds: int.tryParse(decoded['duration']?.toString() ?? ''),
        );
      }

      return YouTubeDownloadResult.failure(
        msg?.isNotEmpty == true ? msg! : 'Failed to generate MP3 link.',
      );
    } on TimeoutException {
      return YouTubeDownloadResult.failure(
        'Request timed out. Please try again.',
      );
    } catch (_) {
      return YouTubeDownloadResult.failure(
        'Network error while calling RapidAPI.',
      );
    }
  }

  static Future<String?> _resolveApiKey() async {
    final saved = await DownloadAccessKeyStore.read();
    return saved;
  }

  static Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return const {};
    }
    return const {};
  }
}
