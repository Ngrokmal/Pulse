import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfileImageCache {
  ProfileImageCache._privateConstructor();
  static final ProfileImageCache instance = ProfileImageCache._privateConstructor();

  final Set<String> _precachedUrls = {};

  final Map<String, CachedNetworkImageProvider> _providers = {};

  ImageProvider providerFor(String url) {
    return _providers.putIfAbsent(url, () => CachedNetworkImageProvider(url));
  }

  Future<void> precache(BuildContext context, {String? avatarUrl, String? coverUrl}) async {
    for (final url in [avatarUrl, coverUrl]) {
      if (url == null || url.isEmpty || _precachedUrls.contains(url)) continue;
      try {
        await precacheImage(providerFor(url), context);
        _precachedUrls.add(url);
      } catch (_) {}
    }
  }

  void evict(String? url) {
    if (url == null || url.isEmpty) return;
    try {
      providerFor(url).evict();
      _precachedUrls.remove(url);
      _providers.remove(url);
    } catch (_) {}
  }
}
