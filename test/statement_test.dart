import 'package:expense_tracker/core/matcher.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/reconcile.dart';
import 'package:expense_tracker/core/statement.dart';
import 'package:flutter_test/flutter_test.dart';

// Layouts copied from real PDF text; names, numbers and ids are made up.
// The real PDF text has trailing spaces on party lines; the parser must not need them.
const momoText = '''
#PAGE 1
Momo Statement
Customer: Jean MUGABO
Number: 250788000111
Period: 2026-11-04 00:00:00 to 2026-11-11 00:00:00
Transaction
Id
Status
Transaction Type
Date
From
To
Amount (RWF)
Fee
(RWF)
Balance
After (RWF)
31847885556
SUCCESSFUL
CUSTOM_PAYMENT
2026-11-10 18:37:20
250788000111
Jean MUGABO
rndps
EKASH EKASH
600
20
8173
31845225745
SUCCESSFUL
PAYMENT
2026-11-10 17:21:33
250788000111
Jean MUGABO
30650820
SAWA CITI LTD. SAWA
CITI LTD.
3600
0
8793
#PAGE 2
Transaction
Id
Status
31840220887
SUCCESSFUL
TRANSFER
2026-11-10 13:12:46
250791700000
THUNES LTD
250788000111
Jean Jean
10210
N/A
12393
31840000000
FAILED
TRANSFER
2026-11-10 12:00:00
250788000111
Jean MUGABO
250780000000
Eric Eric
500
20
12393
End of Report
''';

const equityText = '''
#PAGE 1
Account
Statement
JEAN MUGABO
Account Number
4002000000000
Transaction Details
Payment reference
Value Date
Credit (Money In)
Debit (Money Out)
Balance
TPGYBILL 250788000111 25457113184/329558083400/16-
250788000111 25457113184
25457113184
S1808653
16/01/2026
1,000.00
1,141.00
APP/MTN/250788000111/ACAEF2BD448AA/JEAN MUGABO/
ACAEF2BD448AA
EQACAEF2BD448AA
5080729
13/02/2026
500.00
641.00
MC-FUNDEDNEXT /PURC /625017560393/07-09-202
519896XXXXXX0000
S7893524
14/02/2026
93,877.00
-93,236.00
Total
1,000.00
94,377.00
-93,236.00
''';

List<String> lines(String s) => s.split('\n');

/// The newer Equity layout (Transaction Ref, Credit and Debit columns), one
/// cell per line, with made-up details. One transfer is booked as three rows:
/// the amount, its charge (same Transaction Ref and description), and the SMS
/// charge (reference + "SC").
const newEquity = [
  'Account', 'Statement', 'TEST OWNER', 'Account Number', '4000000000001', 'Currency', 'RWF',
  'Statement Date', '12/11/2026', 'Statement', 'Period', '10/11/2026 - 13/11/2026',
  'Transactions', 'Transaction Details', 'Transaction Ref', 'Value Date', 'Credit', 'Debit', 'Balance',
  'SMS CHARGE', 'A1B2C3D4E5F6SC', '5023751', '13/11/2026', '04.00', '1,536.00',
  'RNDPS EKASH/A1B2C3D4E5F6/0780000001/TEST OWNER', 'A1B2C3D4E5F6', '5023748', '13/11/2026', '20.00', '1,516.00',
  'RNDPS EKASH/A1B2C3D4E5F6/0780000001/TEST OWNER', 'A1B2C3D4E5F6', '5023748', '13/11/2026', '2,000.00', '-484.00',
  'LEDGER FEE', '5023999', '13/11/2026', '500.00', '-984.00',
];

void main() {
  group('Equity fees belong to their transaction', () {
    test('the charge and SMS charge rows fold into the transfer as its fee', () {
      final rows = StatementParser.parse(newEquity)!;
      final transfer = rows.singleWhere((r) => r.amount == 200000);
      expect(transfer.fee, 2400); // RWF 20 + RWF 4, like the SMS
      expect(transfer.refs, contains('A1B2C3D4E5F6'));
      expect(transfer.counterparty, 'TEST OWNER');
      // A charge with no transaction of its own stays, to be added once.
      expect(rows.map((r) => r.amount), unorderedEquals([200000, 50000]));
    });

    test('matched to the alert by reference: nothing added, no fee counted twice', () {
      final rows = StatementParser.parse(newEquity)!;
      final alert = ParsedMessage(
        provider: Provider.equity,
        kind: Kind.transfer,
        direction: Direction.outflow,
        time: DateTime(2026, 11, 13, 0, 8),
        amount: 200000,
        fee: 2400,
        reference: 'A1B2C3D4E5F6',
        counterparty: 'TEST OWNER',
      );
      final me = OwnIdentity(names: const ['Test Owner'], phones: const ['0780000001']);
      final result = StatementReconciler(me).reconcile(rows, TransactionMatcher().match([alert]));
      expect(result.known, hasLength(1));
      expect(result.feeFixes, isEmpty);
      expect(result.missing.map((m) => m.amount), [50000]); // only the ledger fee
    });

    test('newest-first statements: letters-only refs, next-day SMS charge, balances not used', () {
      const lines = [
        'Account Number', '4000000000001', 'Value Date', 'Transaction Details', 'Transaction Ref', 'Credit', 'Debit', 'Balance',
        // Newest first; the SMS charge for the 4 Nov transfer is booked on 5 Nov.
        'SMS CHARGE', 'AQWERTYUIOPLSC', '5020009', '05/11/2026', '04.00', '96.00',
        'RNDPS EKASH/AQWERTYUIOPL/0780000001/TEST OWNER', 'AQWERTYUIOPL', '5020008', '04/11/2026', '20.00', '76.00',
        'RNDPS EKASH/AQWERTYUIOPL/0780000001/TEST OWNER', 'AQWERTYUIOPL', '5020008', '04/11/2026', '4,000.00', '-3,924.00',
      ];
      final rows = StatementParser.parse(lines)!;
      expect(rows.single.amount, 400000);
      expect(rows.single.fee, 2400);
      expect(rows.single.refs, contains('AQWERTYUIOPL'));
      expect(rows.single.balanceKnown, isFalse);
    });

    test('two card payments at one shop on one day stay two payments', () {
      const lines = [
        'Account Number', '4000000000001', 'Value Date', 'Transaction Details', 'Transaction Ref', 'Credit', 'Debit', 'Balance',
        'MC-SHOP ONE /PURC', '5020001', '13/11/2026', '3,000.00', '7,000.00',
        'MC-SHOP ONE /PURC', '5020002', '13/11/2026', '1,000.00', '6,000.00',
      ];
      expect(StatementParser.parse(lines)!.map((r) => (r.amount, r.fee)), [(300000, 0), (100000, 0)]);
    });

    test('an alert that showed a smaller fee gets the statement fee instead', () {
      final rows = StatementParser.parse(newEquity)!;
      final alert = ParsedMessage(
        provider: Provider.equity,
        kind: Kind.expense,
        direction: Direction.outflow,
        time: DateTime(2026, 11, 13, 0, 8),
        amount: 200000,
        fee: 2000,
        reference: 'A1B2C3D4E5F6',
      );
      final result = StatementReconciler(OwnIdentity(names: const [], phones: const []))
          .reconcile(rows, TransactionMatcher().match([alert]));
      expect(result.feeFixes.single.$2, 2400);
    });
  });

  test('only rows from the install day on are kept, by day', () {
    StatementRow row(DateTime t) => StatementRow(
          provider: Provider.equity,
          time: t,
          hasTime: false,
          direction: Direction.outflow,
          amount: 100,
          balance: 0,
          description: 'x',
          refs: const {},
        );
    final rows = [row(DateTime(2026, 11, 10)), row(DateTime(2026, 11, 11)), row(DateTime(2026, 11, 12))];
    // Installed in the afternoon of the 11th: the 11th (date only) still counts.
    expect(rowsSince(rows, DateTime(2026, 11, 11, 15, 30)).map((r) => r.time.day), [11, 12]);
  });

  final me = OwnIdentity(names: ['Jean Mugabo'], phones: ['250788000111']);

  test('MoMo: rows, direction, fees, names, failed rows skipped, page break ignored', () {
    final rows = StatementParser.parse(lines(momoText))!;
    expect(rows, hasLength(3));
    final ekash = rows[0];
    expect(ekash.direction, Direction.outflow);
    expect(ekash.amount, 60000);
    expect(ekash.fee, 2000);
    expect(ekash.balance, 817300);
    expect(ekash.counterparty, 'EKASH');
    expect(ekash.time, DateTime(2026, 11, 10, 18, 37, 20));
    expect(rows[1].counterparty, 'SAWA CITI LTD.');
    expect(rows[2].direction, Direction.inflow);
    expect(rows[2].counterparty, 'THUNES LTD');
    expect(rows[2].fee, 0);
  });

  test('Equity: direction from the balance chain and opening from totals', () {
    final rows = StatementParser.parse(lines(equityText))!;
    expect(rows, hasLength(3));
    expect(rows[0].direction, Direction.inflow);
    expect(rows[0].refs, containsAll(['25457113184', 'S1808653']));
    expect(rows[0].time, DateTime(2026, 1, 16));
    expect(rows[1].direction, Direction.outflow);
    expect(rows[1].refs, contains('ACAEF2BD448AA'));
    expect(rows[1].phone, '250788000111');
    expect(rows[2].counterparty, 'FUNDEDNEXT');
    expect(rows[2].amount, 9387700);
  });

  test('unknown documents are not parsed', () {
    expect(StatementParser.parse(['Hello', 'world']), isNull);
  });

  group('reconcile', () {
    ParsedMessage msg(Provider p, Kind k, Direction d, int rwf, DateTime t,
            {String? ref, String currency = 'RWF', String? who}) =>
        ParsedMessage(
            provider: p, kind: k, time: t, direction: d, amount: rwf * 100, currency: currency, reference: ref, counterparty: who);

    test('MoMo rows: known by id, missing ones added and classified', () {
      final existing = TransactionMatcher().match([
        msg(Provider.mtn, Kind.expense, Direction.outflow, 3600, DateTime(2026, 11, 10, 17, 21, 33), ref: '31845225745'),
        msg(Provider.mtn, Kind.income, Direction.inflow, 10210, DateTime(2026, 11, 10, 13, 12, 46), ref: '31840220887'),
      ]);
      final r = StatementReconciler(me).reconcile(StatementParser.parse(lines(momoText))!, existing);
      expect(r.known, hasLength(2));
      expect(r.missing, hasLength(1));
      expect(r.missing.single.kind, Kind.transfer, reason: 'a payment to EKASH goes to my own Equity wallet');
      expect(r.missing.single.note, 'statement');
    });

    test('importing twice adds nothing new', () {
      final rows = StatementParser.parse(lines(momoText))!;
      final first = StatementReconciler(me).reconcile(rows, []);
      final all = TransactionMatcher().match(first.missing);
      expect(StatementReconciler(me).reconcile(rows, all).missing, isEmpty);
    });

    test('Equity: TPGYBILL confirms the MoMo token payment, and the card row fills the RWF amount', () {
      final existing = TransactionMatcher().match([
        msg(Provider.mtn, Kind.needsReview, Direction.outflow, 1000, DateTime(2026, 1, 16, 7, 34),
            ref: '25457113184', who: 'EQUITY BANK RWANDA'),
        msg(Provider.equity, Kind.expense, Direction.outflow, 64, DateTime(2026, 2, 14, 9, 35),
            currency: 'USD', who: 'FUNDEDNEXT', ref: 'AUTH 1'),
      ]);
      final r = StatementReconciler(me).reconcile(StatementParser.parse(lines(equityText))!, existing);
      expect(r.confirmedTransfers.single.message.reference, '25457113184');
      expect(r.confirmedTransfers.single.kind, Kind.transfer);
      expect(r.foreignAmounts.single.$2, 9387700);
      // The TPGYBILL credit and the send to MoMo had no alert: both added, both transfers.
      expect(r.missing.map((m) => m.kind), [Kind.transfer, Kind.transfer]);
    });
  });
}
