import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hass_bulgarian_voice/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty state shows the microphone and a hint', (tester) async {
    await tester.pumpWidget(const HassVoiceApp());
    await tester.pumpAndSettle();

    expect(find.text('HASS Voice'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.textContaining('Няма добавен gateway'), findsOneWidget);
    expect(find.text('Задръж и говори'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-gateway-title')), findsNothing);
  });

  testWidgets('active gateway is titled above the microphone', (tester) async {
    await tester.pumpWidget(const HassVoiceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_link));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '192.168.1.5:8125');
    await tester.enterText(find.byType(TextField).at(1), 'Вкъщи');
    await tester.tap(find.widgetWithText(FilledButton, 'Добави'));
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('active-gateway-title'));
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).data, 'Вкъщи');
    expect(
      tester.getCenter(title).dy,
      lessThan(tester.getCenter(find.byIcon(Icons.mic)).dy),
    );
  });

  testWidgets('add, long-press and delete a gateway', (tester) async {
    await tester.pumpWidget(const HassVoiceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_link));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '192.168.1.5:8080');
    await tester.tap(find.widgetWithText(FilledButton, 'Добави'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Няма добавен gateway'), findsNothing);
    expect(find.text('192.168.1.5'), findsWidgets);

    await tester.longPress(find.text('192.168.1.5').first);
    await tester.pumpAndSettle();
    expect(find.text('Редактирай'), findsOneWidget);
    expect(find.text('Изтрий'), findsOneWidget);

    await tester.tap(find.text('Изтрий'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Изтрий'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Няма добавен gateway'), findsOneWidget);
  });

  testWidgets('gateway secret is saved, prefilled and can be cleared', (
    tester,
  ) async {
    await tester.pumpWidget(const HassVoiceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_link));
    await tester.pumpAndSettle();

    var fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    expect(tester.widget<TextField>(fields.at(2)).obscureText, isTrue);

    await tester.enterText(fields.at(0), '192.168.1.5:8125');
    await tester.enterText(fields.at(2), 'top-secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Добави'));
    await tester.pumpAndSettle();

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateways_v1'), contains('top-secret'));
    expect(find.textContaining('top-secret'), findsNothing);

    await tester.longPress(find.text('192.168.1.5').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактирай'));
    await tester.pumpAndSettle();

    fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(2)).controller!.text,
      'top-secret',
    );

    await tester.enterText(fields.at(2), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Запази'));
    await tester.pumpAndSettle();

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gateways_v1'), isNot(contains('top-secret')));
  });
}
