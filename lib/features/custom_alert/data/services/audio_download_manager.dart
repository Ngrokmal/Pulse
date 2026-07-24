import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../../core/errors/exceptions.dart';

class AudioDownloadManager {
  final http.Client client;

  const AudioDownloadManager({required this.client});

  Future<List<int>> download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('HTTPS')) {
      throw ServerException(message: 'Invalid alert audio download URL: $url');
    }

    late final http.Response response;
    try {
      response = await client.get(uri).timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw NetworkException(message: 'Alert audio download failed: ${e.message}');
    } on TimeoutException {
      throw NetworkException(message: 'Alert audio download timed out.');
    }

    if (response.statusCode != 200) {
      throw ServerException(message: 'Alert audio download failed (${response.statusCode})');
    }

    return response.bodyBytes;
  }
}
