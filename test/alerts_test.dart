import 'package:expense_tracker/core/matcher.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/parser.dart';
import 'package:expense_tracker/platform/alerts.dart';
import 'package:flutter_test/flutter_test.dart';

RawAlert alert(String package, String title, String text) =>
    RawAlert(package: package, title: title, text: text, postedAt: DateTime(2026, 11, 11, 10));

void main() {
  const body =
      'You have just received RWF 5000.00 4002000000000, REF  S3574951 11 Nov 2026 on eKash. Your new balance is RWF 6540.00';

  test('sender: SMS by title, Equity app by package, others ignored', () {
    expect(alert('com.samsung.android.messaging', 'M-Money', 'x').sender, 'M-Money');
    expect(alert(RawAlert.equityApp, 'OneEquity', body).sender, 'EQUITYBANK');
    expect(alert('com.whatsapp', 'Mom', 'send 500 RWF').sender, isNull);
  });

  test('real capture: MoMo to Equity with app push and SMS becomes one transfer', () {
    // Captured on the phone on Nov 11, 2026 (name and account number replaced).
    final captured = [
      RawAlert(
          package: RawAlert.equityApp,
          title: 'OneEquity',
          text: 'You have just received RWF 1000.00 4002000000000, REF  S3587192 11 Nov 2026 on eKash. Your new balance is RWF 7540.00',
          postedAt: DateTime.fromMillisecondsSinceEpoch(1794416987771)),
      RawAlert(
          package: 'com.google.android.apps.messaging',
          title: 'EQUITYBANK',
          text: 'You have just received RWF 1000.00 4002000000000, REF  S3587192 11 Nov 2026 on eKash. Your new balance is RWF 7540.00',
          postedAt: DateTime.fromMillisecondsSinceEpoch(1794417164425)),
      RawAlert(
          package: 'com.google.android.apps.messaging',
          title: 'M-Money',
          text: 'TransactionId: 31871366761 Your payment of 1000 RWF to JEAN MUGABO at EQUITY BANK with token and ET Id:  SUCCESSFUL at 2026-11-11T19:09:47.427+02:00.Fee:20 RWF. Balance 613 RWF.',
          postedAt: DateTime.fromMillisecondsSinceEpoch(1794417164429)),
    ];
    final parser = MessageParser(OwnIdentity(names: ['Jean Mugabo'], phones: []));
    final matched = TransactionMatcher().match(captured.map((a) => parser.parse(a.sender!, a.text, a.postedAt)!));
    expect(matched, hasLength(2), reason: 'the Equity SMS repeats the app push');
    expect(matched.map((t) => t.kind), everyElement(Kind.transfer));
    expect(matched.first.pair, same(matched.last));
    expect(matched.any((t) => t.inTotals), isFalse);
  });

  test('Equity app push and the same SMS count once', () {
    final parser = MessageParser(OwnIdentity(names: [], phones: []));
    final app = alert(RawAlert.equityApp, 'OneEquity', body);
    final sms = alert('com.samsung.android.messaging', 'EQUITYBANK', body);
    final parsed = [app, sms].map((a) => parser.parse(a.sender!, a.text, a.postedAt)!).toList();
    expect(parsed.first.balance, 654000);
    expect(TransactionMatcher().match(parsed), hasLength(1));
  });
}
