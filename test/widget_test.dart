import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/settings.dart';
import 'package:expense_tracker/widgets/amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppSettings> freshSettings([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return AppSettings.load();
}

void main() {
  test('formatRwf groups digits, signs, and hides', () {
    expect(formatRwf(360000), 'RWF 3,600');
    expect(formatRwf(1234567800), 'RWF 12,345,678');
    expect(formatRwf(-52000), '- RWF 520');
    expect(formatRwf(760000, signed: true), '+ RWF 7,600');
    expect(formatRwf(360000, hidden: true), 'RWF •••••');
    expect(formatRwf(-52000, hidden: true), '- RWF •••••');
  });

  testWidgets('app starts on Home and switches tabs', (tester) async {
    await tester.pumpWidget(ExpenseTrackerApp(settings: await freshSettings()));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsNWidgets(2)); // tab label + page title
  });

  testWidgets('eye button hides amounts and is remembered', (tester) async {
    final settings = await freshSettings();
    await tester.pumpWidget(ExpenseTrackerApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide amounts'));
    await tester.pump();
    expect(settings.hideAmounts, isTrue);
    expect(find.byTooltip('Show amounts'), findsOneWidget);
    expect((await freshSettingsKeepingPrefs()).hideAmounts, isTrue);
  });

  testWidgets('theme setting switches the app to dark', (tester) async {
    final settings = await freshSettings({'themeMode': 'dark'});
    await tester.pumpWidget(ExpenseTrackerApp(settings: settings));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
  });
}

/// Reloads settings from the same mock storage, like reopening the app.
Future<AppSettings> freshSettingsKeepingPrefs() => AppSettings.load();
