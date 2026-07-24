import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfileImageCache {
  ProfileImageCache._privateConstructor();
  static final ProfileImageCache instance = ProfileImageCache._privateConstructor();

  final Set<String> _precachedUrls = {};

  // BUG FIX (image provider must never be recreated when the URL hasn't
  // changed): CachedNetworkImageProvider does implement value-equality
  // (same url -> "==" true), so Flutter's own ImageCache would already
  // de-dupe repeated same-URL instances in most cases. This map makes that
  // an explicit, auditable guarantee instead of an implicit one — every
  // caller that needs an ImageProvider for a given URL gets back the exact
  // same object every time, for as long as that URL is in use. A URL change
  // is simply a different map key; nothing needs manual invalidation.
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
