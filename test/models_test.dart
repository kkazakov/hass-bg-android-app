import 'package:flutter_test/flutter_test.dart';
import 'package:hass_bulgarian_voice/models.dart';
import 'package:hass_bulgarian_voice/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizeUrl adds a scheme and strips trailing slashes', () {
    expect(
      Gateway.normalizeUrl(' 192.168.1.5:8080/ '),
      'http://192.168.1.5:8080',
    );
    expect(
      Gateway.normalizeUrl('https://example.com:8443/'),
      'https://example.com:8443',
    );
    expect(Gateway.normalizeUrl(''), '');
  });

  test('defaultName falls back to the host', () {
    expect(Gateway.defaultName('http://100.101.102.12:8080'), '100.101.102.12');
    expect(Gateway.defaultName('not a url'), 'Gateway');
  });

  test('CommandResult parses an action reply', () {
    final result = CommandResult.fromJson({
      'kind': 'action',
      'speak': false,
      'text': 'Изключих лампата в хола.',
      'transcript': 'изключи лампата в хола',
      'audio_url': null,
      'matched': {'intent': 'HallLightOff', 'score': 100.0},
      'timings': {'total_ms': 121.0},
    });
    expect(result.noMatch, isFalse);
    expect(result.intent, 'HallLightOff');
    expect(result.matchScore, 100.0);
    expect(result.audioUrl, isNull);
  });

  test('CommandResult parses a no-match reply', () {
    final result = CommandResult.fromJson({
      'kind': 'no_match',
      'speak': false,
      'text': 'Не разбрах. Повторете, моля.',
      'transcript': 'пусни музика',
      'matched': null,
    });
    expect(result.noMatch, isTrue);
    expect(result.intent, isNull);
  });

  test('store round-trips gateways and the active id', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GatewayStore();
    final gateways = [
      Gateway(id: 'a', name: 'Вкъщи', url: 'http://192.168.1.5:8080'),
      Gateway(id: 'b', name: 'Офис', url: 'http://10.0.0.2:8080'),
    ];

    await store.save(gateways, 'b');
    final loaded = await store.load();

    expect(loaded.gateways, hasLength(2));
    expect(loaded.gateways.first.name, 'Вкъщи');
    expect(loaded.activeId, 'b');
  });

  test('store falls back to the first gateway when active is stale', () async {
    SharedPreferences.setMockInitialValues({
      'gateways_v1':
          '[{"id":"a","name":"Вкъщи","url":"http://192.168.1.5:8080"}]',
      'active_gateway_v1': 'gone',
    });
    final loaded = await GatewayStore().load();
    expect(loaded.activeId, 'a');
  });
}
