import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hass_bulgarian_voice/api.dart';
import 'package:hass_bulgarian_voice/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;
  late String wavPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bg_voice_api_test');
    wavPath = '${tempDir.path}/command.wav';
    await File(wavPath).writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Gateway gateway({String secret = ''}) => Gateway(
    id: 'g',
    name: 'Test',
    url: 'http://gateway.test:8125',
    secret: secret,
  );

  http.Response jsonResponse(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  test('sendCommand sends X-API-Key when the gateway has a secret', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://gateway.test:8125/v1/voice');
      expect(request.headers['X-API-Key'], 'top-secret');
      return jsonResponse({
        'kind': 'action',
        'speak': false,
        'text': 'Готово.',
        'transcript': 'включи лампата',
      });
    });
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    final result = await api.sendCommand(
      gateway: gateway(secret: ' top-secret '),
      wavPath: wavPath,
    );

    expect(result.text, 'Готово.');
  });

  test('sendCommand omits X-API-Key for a keyless gateway', () async {
    final client = MockClient((request) async {
      expect(request.headers.containsKey('X-API-Key'), isFalse);
      return jsonResponse({
        'kind': 'no_match',
        'speak': false,
        'text': 'Не разбрах.',
        'transcript': 'нещо',
      });
    });
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    final result = await api.sendCommand(gateway: gateway(), wavPath: wavPath);

    expect(result.noMatch, isTrue);
  });

  test('fetchAudio downloads reply audio with the secret', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'http://gateway.test:8125/v1/audio/clip.mp3',
      );
      expect(request.headers['X-API-Key'], 'top-secret');
      return http.Response.bytes(
        const [1, 2, 3],
        200,
        headers: {'content-type': 'audio/mpeg'},
      );
    });
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    final reply = await api.fetchAudio(
      gateway: gateway(secret: 'top-secret'),
      relative: '/v1/audio/clip.mp3',
    );

    expect(reply.bytes, const [1, 2, 3]);
    expect(reply.mimeType, 'audio/mpeg');
  });

  test('fetchAudio omits X-API-Key for a keyless gateway', () async {
    final client = MockClient((request) async {
      expect(request.headers.containsKey('X-API-Key'), isFalse);
      return http.Response.bytes(const [1], 200);
    });
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    await api.fetchAudio(gateway: gateway(), relative: '/v1/audio/clip.wav');
  });

  test('fetchAudio does not leak the secret to another origin', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://cdn.test/clip.mp3');
      expect(request.headers.containsKey('X-API-Key'), isFalse);
      return http.Response.bytes(const [1], 200);
    });
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    await api.fetchAudio(
      gateway: gateway(secret: 'top-secret'),
      relative: 'http://cdn.test/clip.mp3',
    );
  });

  test('a 401 explains the missing or wrong gateway secret', () async {
    final client = MockClient(
      (_) async =>
          jsonResponse({'detail': 'invalid or missing X-API-Key'}, 401),
    );
    final api = GatewayClient(client: client);
    addTearDown(api.close);

    await expectLater(
      api.fetchAudio(
        gateway: gateway(secret: 'wrong'),
        relative: '/v1/audio/clip.mp3',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Gateway изисква валидна тайна (X-API-Key)',
        ),
      ),
    );
  });
}
