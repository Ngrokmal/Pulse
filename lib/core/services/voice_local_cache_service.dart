import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' show sha1;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class VoiceLocalCacheService {
  VoiceLocalCacheService._privateConstructor();
  static final VoiceLocalCacheService instance = VoiceLocalCacheService._privateConstructor();

  static const String _cacheDirName = 'voice_cache';
  final http.Client _client = http.Client();

  Future<File?> getCachedFile(String url) async {
    final file = await _fileFor(url);
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  Future<File> getOrDownload(String url) async {
    final cached = await getCachedFile(url);
    if (cached != null) return cached;

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Voice download failed with status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final file = await _fileFor(url);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } on SocketException {
      throw const SocketException(
        'No internet connection to download voice message.',
      );
    } on TimeoutException {
      throw TimeoutException(
        'Connection timed out while downloading voice message.',
      );
    } catch (e) {
      if (e is SocketException || e is TimeoutException || e is HttpException) {
        rethrow;
      }
      throw Exception('Failed to load voice message: $e');
    }
  }

  Future<void> seedFromLocalFile({required String url, required File localFile}) async {
    try {
      if (!await localFile.exists()) return;
      final existing = await getCachedFile(url);
      if (existing != null) return;
      final target = await _fileFor(url);
      await localFile.copy(target.path);
    } catch (_) {
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