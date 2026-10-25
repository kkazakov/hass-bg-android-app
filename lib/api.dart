import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GatewayClient {
  Future<CommandResult> sendCommand({
    required Gateway gateway,
    required String wavPath,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('${gateway.url}/v1/voice');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio', wavPath));
      final streamed = await request.send().timeout(timeout);
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

  Uri audioUri(Gateway gateway, String relative) {
    return Uri.parse(gateway.url).resolve(relative);
  }

  String _describeError(http.Response response) {
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
