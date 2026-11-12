import 'package:expense_tracker/core/own_accounts.dart';
import 'package:expense_tracker/data/ledger_controller.dart';
import 'package:expense_tracker/data/ledger_store.dart';
import 'package:expense_tracker/platform/alerts.dart';
import 'package:expense_tracker/platform/popup_settings.dart';
import 'package:expense_tracker/popup/popup_logic.dart';
import 'package:expense_tracker/screens/identity_screen.dart';
import 'package:expense_tracker/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone side, answering at once (tests have no Android behind the channels).
class _NoPhone extends AlertsChannel {
  const _NoPhone();
  @override
  Future<bool> isListenerEnabled() async => true;
  @override
  Future<List<RawAlert>> allAlerts() async => const [];
  @override
  Future<DateTime?> installedAt() async => null;
  @override
  Future<void> resetLocal() async {}
  @override
  Stream<RawAlert> get alerts => const Stream.empty();
}

class _NoPopups extends PopupSettingsChannel {
  const _NoPopups();
  @override
  Future<List<PopupDecision>> takeDecisions() async => const [];
  @override
  Future<void> setConfig(PopupConfig config) async {}
}

void main() {
  test('a phone number tells MTN from Airtel', () {
    expect(accountTypeOfPhone('0781234567'), AccountType.mtn);
    expect(accountTypeOfPhone('250791234567'), AccountType.mtn);
    expect(accountTypeOfPhone('0731234567'), AccountType.airtel);
    expect(accountTypeOfPhone('07*****567'), isNull);
  });

  test('account numbers get a light check', () {
    expect(AccountType.mtn.check(''), isNotNull);
    expect(AccountType.mtn.check('0781'), isNotNull);
    expect(AccountType.mtn.check('078 123 4567'), isNull);
    expect(AccountType.equity.check('12345'), isNotNull);
    expect(AccountType.equity.check('4000000000001'), isNull);
  });

  testWidgets('setup needs a name and an account, one per row, and saves them', (tester) async {
    // A tall screen, so the whole form (and the Continue button) is built.
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final store = MemoryLedgerStore();
    final c = LedgerController(store, alerts: const _NoPhone(), popups: const _NoPopups())..start();
    await tester.pumpWidget(SettingsScope(
      settings: settings,
      child: MaterialApp(home: LedgerScope(controller: c, child: const SetupScreen())),
    ));
    await tester.pumpAndSettle();
    expect(c.setupDone, isFalse);

    // Nothing filled in: it stays on setup.
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Name 1'), 'Test Owner');
    await tester.enterText(find.widgetWithText(TextField, 'MTN MoMo number'), '0780000001');
    await tester.ensureVisible(find.text('Add another account'));
    await tester.tap(find.text('Add another account'));
    await tester.pumpAndSettle();
    // The new row starts as MTN; switch it to Equity.
    await tester.ensureVisible(find.text('Equity').last);
    await tester.tap(find.text('Equity').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Equity account number'), '4000000000001');

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.setupDone, isTrue);
    expect(c.ownNames, ['Test Owner']);
    expect(c.ownAccounts.map((a) => a.type), [AccountType.mtn, AccountType.equity]);
    expect(store.profile['phones'], ['0780000001', '4000000000001']);

    // Erase all data: everything goes, setup is needed again, statements count from today.
    store.addIn(LedgerStore.loans, {'side': 'owedToMe', 'person': 'X', 'amount': 100, 'createdAt': 0});
    await c.eraseAll();
    await tester.pumpAndSettle();
    expect(c.setupDone, isFalse);
    expect(store.docsOf(LedgerStore.loans), isEmpty);
    expect(store.profile.keys, ['trackingSince']);
    final today = DateTime.now();
    expect(c.trackingSince, DateTime(today.year, today.month, today.day));
    c.dispose();
  });
}
