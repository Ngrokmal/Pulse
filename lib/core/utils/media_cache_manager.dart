import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MediaCacheManager {
  MediaCacheManager._privateConstructor();
  static final MediaCacheManager instance = MediaCacheManager._privateConstructor();

  void evictImageUrls(Iterable<String?> urls) {
    try {
      final ImageCache imageCache = PaintingBinding.instance.imageCache;
      final seen = <String>{};
      for (final url in urls) {
        if (url == null || url.isEmpty || !seen.add(url)) continue;
        imageCache.evict(CachedNetworkImageProvider(url));
      }
    } catch (e) {
      debugPrint("MediaCacheManager Error: ${e.toString()}");
    }
  }

  void forceFlushImageMemory() {
    try {
      final ImageCache imageCache = PaintingBinding.instance.imageCache;

      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      debugPrint("MediaCacheManager Error: ${e.toString()}");
    }
  }
}
