import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A reply audio clip downloaded from the gateway.
class AudioReply {
  AudioReply({required this.bytes, this.mimeType});

  final Uint8List bytes;
  final String? mimeType;
}

class GatewayClient {
  GatewayClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  /// `X-API-Key` is optional: keyless gateways must keep working, so the
  /// header is sent only when the saved gateway has a non-empty secret.
  Map<String, String> _headers(Gateway gateway) => gateway.hasSecret
      ? {'X-API-Key': gateway.secret.trim()}
      : const <String, String>{};

  Future<CommandResult> sendCommand({
    required Gateway gateway,
    required String wavPath,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('${gateway.url}/v1/voice');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers(gateway))
        ..files.add(await http.MultipartFile.fromPath('audio', wavPath));
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw ApiException(_describeError(response));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw ApiException('Неочакван отговор от gateway');
      }
      return CommandResult.fromJson(decoded);
    } on TimeoutException {
      throw ApiException('Gateway не отговаря (timeout)');
    } on SocketException {
      throw ApiException('Няма връзка с ${gateway.url}');
    } on HttpException catch (error) {
      throw ApiException('Мрежова грешка: ${error.message}');
    } on http.ClientException catch (error) {
      throw ApiException('Мрежова грешка: ${error.message}');
    } on FormatException {
      throw ApiException('Невалиден отговор от gateway');
    }
  }

  /// Downloads reply audio with the gateway secret attached. `audioplayers`'
  /// URL source cannot send headers, so keyed gateways need this fetch.
  Future<AudioReply> fetchAudio({
    required Gateway gateway,
    required String relative,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final base = Uri.parse(gateway.url);
    final uri = audioUri(gateway, relative);
    // Never leak the key to a third-party host if a (possibly tampered with)
    // audio_url is absolute. The gateway itself returns relative paths.
    final headers = _sameOrigin(base, uri)
        ? _headers(gateway)
        : const <String, String>{};
    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw ApiException('Gateway не отговаря (timeout)');
    } on SocketException {
      throw ApiException('Няма връзка с ${gateway.url}');
    } on HttpException catch (error) {
      throw ApiException('Мрежова грешка: ${error.message}');
    } on http.ClientException catch (error) {
      throw ApiException('Мрежова грешка: ${error.message}');
    }
    if (response.statusCode != 200) {
      throw ApiException(_describeError(response));
    }
    return AudioReply(
      bytes: response.bodyBytes,
      mimeType: response.headers['content-type'],
    );
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  Uri audioUri(Gateway gateway, String relative) {
    return Uri.parse(gateway.url).resolve(relative);
  }

  String _describeError(http.Response response) {
    if (response.statusCode == 401) {
      return 'Gateway изисква валидна тайна (X-API-Key)';
    }
    var detail = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] is String) {
        detail = decoded['detail'] as String;
      }
    } catch (_) {
      // Non-JSON error body; fall back to the status code.
    }
    final suffix = detail.isEmpty ? '' : ': $detail';
    return 'Gateway върна ${response.statusCode}$suffix';
  }
}
