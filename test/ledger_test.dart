import 'package:expense_tracker/core/categories.dart';
import 'package:expense_tracker/core/ledger.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/report.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 11, 10, 9); // a Tuesday

ParsedMessage msg(
  Provider p,
  Kind kind,
  Direction dir,
  int rwf, {
  int minutes = 0,
  int fee = 0,
  int? balance,
  String? ref,
  String? who,
  String currency = 'RWF',
}) =>
    ParsedMessage(
      provider: p,
      kind: kind,
      direction: dir,
      time: t0.add(Duration(minutes: minutes)),
      amount: rwf * 100,
      fee: fee * 100,
      balance: balance == null ? null : balance * 100,
      reference: ref,
      counterparty: who,
      currency: currency,
    );

var _n = 0;
TxRecord rec(ParsedMessage m, {String? category, Kind? kindOverride, bool accepted = false, TxSource source = TxSource.alert}) =>
    TxRecord(id: 'r${_n++}', source: source, message: m, category: category, kindOverride: kindOverride, accepted: accepted);

void main() {
  group('Ledger', () {
    test('a new expense is pending until it has a category', () {
      final l = Ledger.build([rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 3600, who: 'Shop'))]);
      expect(l.pending, hasLength(1));
      expect(l.reviewCount, 1);

      final done = Ledger.build([rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 3600), category: 'Transport')]);
      expect(done.pending, isEmpty);
      expect(done.txs.single.confirmed, isTrue);
    });

    test('flags a balance gap, and an entry dated before it explains the gap', () {
      final first = rec(msg(Provider.mtn, Kind.income, Direction.inflow, 1000, balance: 10000, ref: '1'), category: 'Salary');
      final second = rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, minutes: 60, balance: 8000, ref: '2'),
          category: 'Transport');
      final gap = Ledger.build([first, second]);
      expect(gap.openMismatches, hasLength(1));
      expect(gap.openMismatches.single.gap, -100000);
      expect(gap.balances[Provider.mtn]!.balance, 800000);

      final cash = rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, minutes: 30),
          category: 'Food and drinks', source: TxSource.manual);
      expect(Ledger.build([first, second, cash]).openMismatches, isEmpty);
    });

    test('an accepted gap leaves the review list', () {
      final first = rec(msg(Provider.mtn, Kind.income, Direction.inflow, 1000, balance: 10000, ref: '1'), category: 'Salary');
      final second = rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, minutes: 60, balance: 8000, ref: '2'),
          category: 'Transport', accepted: true);
      final l = Ledger.build([first, second]);
      expect(l.mismatches, hasLength(1));
      expect(l.openMismatches, isEmpty);
    });

    test('a repeated alert counts once', () {
      final a = msg(Provider.equity, Kind.expense, Direction.outflow, 500, ref: 'A1');
      final l = Ledger.build([rec(a), rec(msg(Provider.equity, Kind.expense, Direction.outflow, 500, minutes: 300, ref: 'A1'))]);
      expect(l.txs, hasLength(1));
    });

    test('without my names set, a send and a receive naming the same person pair as a transfer', () {
      ParsedMessage person(Provider p, Kind k, Direction d, String who, {int seconds = 0}) => ParsedMessage(
            provider: p,
            kind: k,
            direction: d,
            time: t0.add(Duration(seconds: seconds)),
            amount: 500000,
            counterparty: who,
            isPerson: true,
            reference: '$p$seconds',
          );
      final l = Ledger.build([
        rec(person(Provider.mtn, Kind.expense, Direction.outflow, 'TEST  OWNER TEST OWNER')),
        rec(person(Provider.equity, Kind.income, Direction.inflow, 'Owner Test', seconds: 20)),
      ]);
      expect(l.txs.every((t) => t.kind == Kind.transfer), isTrue);
      expect(l.pending, isEmpty);
      expect(l.learnedNames, hasLength(1));

      // Different people with the same amount at the same time stay what they are.
      final other = Ledger.build([
        rec(person(Provider.mtn, Kind.expense, Direction.outflow, 'Friend One')),
        rec(person(Provider.equity, Kind.income, Direction.inflow, 'Friend Two', seconds: 20)),
      ]);
      expect(other.pending, hasLength(2));
    });

    test('I can say what an unknown message is', () {
      final m = msg(Provider.mtn, Kind.needsReview, Direction.outflow, 2000);
      expect(Ledger.build([rec(m)]).unknown, hasLength(1));
      final l = Ledger.build([rec(m, kindOverride: Kind.expense)]);
      expect(l.unknown, isEmpty);
      expect(l.pending, hasLength(1));
    });

    test('one foreign charge between two balances gets its RWF cost', () {
      final l = Ledger.build([
        rec(msg(Provider.equity, Kind.income, Direction.inflow, 100, balance: 50000, ref: 'x'), category: 'Salary'),
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 20, minutes: 10, currency: 'USD', who: 'CLAUDE.AI'),
            category: 'Subscriptions and software'),
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 1000, minutes: 20, balance: 20000, ref: 'y'),
            category: 'Transport'),
      ]);
      final usd = l.txs.firstWhere((t) => t.m.currency == 'USD');
      expect(usd.resolvedRwf, 2900000);
      expect(l.openMismatches, isEmpty);
    });
  });

  group('Report', () {
    test('totals count confirmed items only, fees as spending, transfers left out', () {
      final txs = Ledger.build([
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 3000, fee: 100), category: 'Food and drinks'),
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 700, minutes: 1)), // pending
        rec(msg(Provider.airtel, Kind.income, Direction.inflow, 10000, minutes: 2), category: 'Salary'),
        rec(msg(Provider.equity, Kind.transfer, Direction.outflow, 5000, minutes: 3, fee: 50, ref: 't1')),
        rec(msg(Provider.mtn, Kind.transfer, Direction.inflow, 5000, minutes: 3, ref: 't2')),
      ]).txs;
      final month = Period.containing(PeriodKind.month, t0);

      final all = Report.build(txs, month).totals;
      expect(all.income, 1000000);
      expect(all.spent, 300000 + 10000 + 5000);
      expect(all.pendingCount, 1);
      expect(all.pendingAmount, 70000);
      expect(all.topSpending.first.name, 'Food and drinks');
      expect(all.spending[feesCategory]!.amount, 15000);
      expect(all.movedIn, 0);

      final mtn = Report.build(txs, month, account: Provider.mtn).totals;
      expect(mtn.movedIn, 500000);
      expect(mtn.income, 0);
    });

    test('a hidden account drops out of the totals and comes back whole', () {
      final txs = Ledger.build([
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 3000), category: 'Food and drinks'),
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 9000, minutes: 1), category: 'Transport'),
        rec(msg(Provider.equity, Kind.transfer, Direction.outflow, 5000, minutes: 2, ref: 'e1')),
        rec(msg(Provider.mtn, Kind.transfer, Direction.inflow, 5000, minutes: 2, ref: 'm1')),
      ]).txs;
      final month = Period.containing(PeriodKind.month, t0);

      final all = Report.build(txs, month);
      expect(all.totals.spent, 1200000);
      expect(all.totals.movedIn, 0); // a transfer between shown accounts is invisible

      final noEquity = Report.build(txs, month, hidden: {Provider.equity});
      expect(noEquity.totals.spent, 300000);
      expect(noEquity.totals.movedIn, 500000); // money arrived from the hidden account
      expect(noEquity.byAccount.map((a) => a.provider), isNot(contains(Provider.equity)));

      // Shown again: the same transactions, so the figures are complete.
      expect(Report.build(txs, month, hidden: const {}).totals.spent, 1200000);
    });

    test('a reversed payment does not count', () {
      final txs = Ledger.build([
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 4000, who: 'SHOP'), category: 'Other'),
        rec(msg(Provider.equity, Kind.cancel, Direction.inflow, 4000, minutes: 5, who: 'SHOP')),
      ]).txs;
      expect(Report.build(txs, Period.containing(PeriodKind.day, t0)).totals.spent, 0);
    });

    test('per-account closing balance is the last one in the period', () {
      final txs = Ledger.build([
        rec(msg(Provider.mtn, Kind.income, Direction.inflow, 1000, balance: 9000, ref: '1'), category: 'Salary'),
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, minutes: 1, balance: 8000, ref: '2'), category: 'Other'),
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, minutes: 60 * 48, balance: 7000, ref: '3'),
            category: 'Other'),
      ]).txs;
      final r = Report.build(txs, Period.containing(PeriodKind.day, t0));
      final mtn = r.byAccount.firstWhere((a) => a.provider == Provider.mtn);
      expect(mtn.closing, 800000);
      expect(mtn.totals.spent, 100000);
    });
  });

  group('Period', () {
    test('weeks run Monday to Sunday', () {
      final w = Period.containing(PeriodKind.week, t0);
      expect(w.start, DateTime(2026, 11, 9));
      expect(w.end, DateTime(2026, 11, 16));
      expect(w.shift(-1).start, DateTime(2026, 11, 2));
    });

    test('trend points: days of the week, weeks of the month, months of the year', () {
      expect(Period.containing(PeriodKind.day, t0).trend(), hasLength(7));
      // November 2026 starts on a Sunday: its weeks start 26 Oct ... 30 Nov.
      final weeks = Period.containing(PeriodKind.month, t0).trend();
      expect(weeks, hasLength(6));
      expect(weeks.first.$2.start, DateTime(2026, 10, 26));
      expect(weeks.last.$2.start, DateTime(2026, 11, 30));
      expect(weeks.first.$1, '26 Oct');
      expect(Period.containing(PeriodKind.year, t0).trend(), hasLength(12));
      final week = Period.containing(PeriodKind.week, t0).trend();
      expect(week, hasLength(7));
      expect(week.first.$2.start, DateTime(2026, 11, 9)); // Monday of t0's week
    });

    test('custom range includes both ends', () {
      final p = Period.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 3));
      expect(p.contains(DateTime(2026, 11, 3, 23, 59)), isTrue);
      expect(p.contains(DateTime(2026, 11, 4)), isFalse);
      expect(p.trend(), hasLength(3));
    });
  });
}
