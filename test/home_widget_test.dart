import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hass_bulgarian_voice/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty state shows the microphone and a hint', (tester) async {
    await tester.pumpWidget(const BgVoiceApp());
    await tester.pumpAndSettle();

    expect(find.text('BG Voice'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.textContaining('Няма добавен gateway'), findsOneWidget);
    expect(find.text('Задръж и говори'), findsOneWidget);
  });

  testWidgets('add, long-press and delete a gateway', (tester) async {
    await tester.pumpWidget(const BgVoiceApp());
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
}
