import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_theme_state.dart';

class ThemeImageCache {
  static final CacheManager _cacheManager = CacheManager(
    Config(
      'zmusic_theme_backgrounds',
      stalePeriod: const Duration(days: 3650),
      maxNrOfCacheObjects: 40,
      repo: JsonCacheInfoRepository(databaseName: 'zmusicThemeCache'),
      fileService: HttpFileService(),
    ),
  );

  static ImageProvider provider(String imageUrl) {
    return CachedNetworkImageProvider(imageUrl, cacheManager: _cacheManager);
  }

  static Future<void> prefetchUrl(String imageUrl) async {
    try {
      await _cacheManager.downloadFile(imageUrl, key: imageUrl);
    } catch (_) {}
  }

  static Future<void> prefetchAllThemes() async {
    for (final preset in AppThemeState.presets) {
      await prefetchUrl(preset.backgroundImageUrl);
    }
  }
}
