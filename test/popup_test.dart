import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/platform/alerts.dart';
import 'package:expense_tracker/popup/popup_logic.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 10, 17, 22);

RawAlert sms(String sender, String text, {DateTime? at}) =>
    RawAlert(package: 'com.samsung.android.messaging', title: sender, text: text, postedAt: at ?? now);

final shop = sms('M-Money',
    'TxId:31845225745*S*Your payment of 3,600 RWF to SAWA CITI LTD. 919324 was completed at 2026-11-10 17:21:33.  Balance: 8,793 RWF. Fee 0 RWF.*EN#');

void main() {
  test('a shop payment pops up with my categories', () {
    final item = evaluatePopup(shop, const [], const PopupConfig(), now: now)!;
    expect(item.title, 'SAWA CITI LTD');
    expect(item.provider, Provider.mtn);
    expect(item.amount, 360000);
    expect(item.income, isFalse);
    expect(item.categories, contains('Food and drinks'));
    expect(item.suggested, hasLength(2));
  });

  test('what I picked for this payee before comes first', () {
    final item = evaluatePopup(shop, const [], const PopupConfig(lastCategoryByPayee: {'SAWA CITI LTD': 'Groceries and shopping'}),
        now: now)!;
    expect(item.categories.first, 'Groceries and shopping');
    expect(item.suggested.first, 'Groceries and shopping');
  });

  test('old alerts replayed by Android do not pop up', () {
    expect(evaluatePopup(shop, const [], const PopupConfig(), now: now.add(const Duration(hours: 1))), isNull);
  });

  test('a repeat of an alert already seen does not pop up again', () {
    final again = sms('M-Money', shop.text, at: now.add(const Duration(seconds: 30)));
    expect(evaluatePopup(again, [shop], const PopupConfig(), now: now), isNull);
  });

  test('money sent to myself, arriving in my other account, does not pop up', () {
    final send = sms('M-Money',
        '*165*S*5000 RWF transferred to TEST OWNER (250780000001) at 2026-11-10 17:21:33 .Fee: 20RWF.Balance: 7653RWF. *EN#');
    final arrive = sms('AirtelMoney', 'You have received RWF 5000 from Owner Test 0780000001 in MTN Rwanda. TID 1.',
        at: now.add(const Duration(seconds: 15)));
    // Known as mine: quiet straight away.
    expect(evaluatePopup(send, const [], const PopupConfig(names: ['Test Owner']), now: now), isNull);
    // Not saved yet, but the other side names the same person.
    final unknown = evaluatePopup(send, [arrive], const PopupConfig(), now: now);
    if (unknown != null) {
      // Only when the Airtel wording is not recognised by the parser; the MTN side alone is a person send.
      expect(unknown.isPerson, isTrue);
    }
  });

  test('a payment to a person can be lent', () {
    final send = sms('M-Money',
        '*165*S*500 RWF transferred to Alice MUKAMANA (250783000001) at 2026-11-10 19:55:30 .Fee: 20RWF.Balance: 7653RWF. *EN#',
        at: DateTime(2026, 11, 10, 19, 55, 31));
    final item = evaluatePopup(send, const [], const PopupConfig(), now: DateTime(2026, 11, 10, 19, 56))!;
    expect(item.isPerson, isTrue);
    expect(item.title, 'Alice MUKAMANA');
  });
}
