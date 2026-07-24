import 'dart:io';
import 'package:crypto/crypto.dart' show sha1;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Bug 4/5 fix: voice messages were always streamed from the network URL on
/// every play — no local caching at all. This gives both directions of
/// WhatsApp-style behavior:
///
/// - SENDER: the file that was just recorded/uploaded is seeded into this
///   cache the moment upload succeeds (see `chat_bloc.dart`'s
///   `_MediaUploadedEvent` handler), so the sender's own bubble never
///   re-downloads its own voice message.
/// - RECEIVER: the first `getOrDownload(url)` call downloads once and
///   writes to disk; every subsequent call (including fully offline, once
///   cached) returns the local file with zero network access.
///
/// Persisted under the app's support directory (not the OS temp dir used
/// for in-progress recordings) so cached playback audio survives longer
/// and isn't subject to the more aggressive temp-dir cleanup some OEMs do.
class VoiceLocalCacheService {
  VoiceLocalCacheService._privateConstructor();
  static final VoiceLocalCacheService instance = VoiceLocalCacheService._privateConstructor();

  static const String _cacheDirName = 'voice_cache';
  final http.Client _client = http.Client();

  /// Returns the cached local file for [url] if it already exists on disk,
  /// without touching the network. Null if not cached yet.
  Future<File?> getCachedFile(String url) async {
    final file = await _fileFor(url);
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  /// Returns the local file for [url] — from cache if present (works fully
  /// offline in that case), otherwise downloads it once and caches it for
  /// every future call. Throws if not cached and the download fails (e.g.
  /// offline with nothing cached yet — there is nothing local to fall back
  /// to in that case).
  Future<File> getOrDownload(String url) async {
    final cached = await getCachedFile(url);
    if (cached != null) return cached;

    final response = await _client.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Voice download failed with status ${response.statusCode}', uri: Uri.parse(url));
    }
    final file = await _fileFor(url);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  /// Seeds the cache for [url] directly from a file already on disk —
  /// avoids a redundant round-trip download for the sender's own
  /// just-uploaded recording, which is already sitting locally. No-op if
  /// something is already cached for this URL, or if [localFile] no longer
  /// exists (e.g. temp file already cleaned up).
  Future<void> seedFromLocalFile({required String url, required File localFile}) async {
    try {
      if (!await localFile.exists()) return;
      final existing = await getCachedFile(url);
      if (existing != null) return;
      final target = await _fileFor(url);
      await localFile.copy(target.path);
    } catch (_) {
      // Best-effort only — worst case the receiver-style download-on-first-
      // play path below still covers it correctly, just with one extra
      // network round trip the first time this bubble is played.
    }
  }

  Future<File> _fileFor(String url) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/$_cacheDirName');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final key = sha1.convert(url.codeUnits).toString();
    return File('${cacheDir.path}/$key.m4a');
  }
}
