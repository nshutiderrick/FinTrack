import 'package:expense_tracker/core/balance.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

final t = DateTime(2026, 11, 10);

ParsedMessage tx(Direction d, int rwf, {int fee = 0, int? balance, String currency = 'RWF', Provider p = Provider.mtn}) =>
    ParsedMessage(
      provider: p,
      kind: d == Direction.inflow ? Kind.income : Kind.expense,
      time: t,
      direction: d,
      amount: rwf * 100,
      fee: fee * 100,
      balance: balance == null ? null : balance * 100,
      currency: currency,
    );

void main() {
  group('Equity placeholder 0', () {
    ParsedMessage eq(Direction d, int rwf, int? balance, int minute) => ParsedMessage(
          provider: Provider.equity,
          kind: d == Direction.inflow ? Kind.income : Kind.expense,
          direction: d,
          time: DateTime(2026, 11, 10, 9, minute),
          amount: rwf * 100,
          balance: balance == null ? null : balance * 100,
        );

    test('a 0 balance is taken as not shown, and the next real one checks the total', () {
      final t = BalanceTracker();
      expect(t.apply(eq(Direction.inflow, 1000, 20000, 0)), isNull); // sets 20,000
      expect(t.apply(eq(Direction.outflow, 5000, 0, 1)), isNull); // "balance 0": not a mismatch
      expect(t.lastShowedBalance, isFalse);
      expect(t.balanceOf(Provider.equity), 1500000); // carried on from the last real figure
      expect(t.apply(eq(Direction.outflow, 2000, 0, 2)), isNull);
      expect(t.balanceOf(Provider.equity), 1300000);
      // The bank shows the balance again: 12,000 instead of the 13,000 expected.
      final gap = t.apply(eq(Direction.outflow, 1000, 11000, 3)) as BalanceMismatch;
      expect(gap.expected, 1200000);
      expect(gap.gap, -100000);
    });

    test('a real 0 when the expected balance is 0 is accepted', () {
      final t = BalanceTracker()..setStarting(Provider.equity, 500000);
      expect(t.apply(eq(Direction.outflow, 5000, 0, 0)), isNull);
      expect(t.lastShowedBalance, isTrue);
    });

    test('a 0 on the very first Equity message does not become the starting balance', () {
      final t = BalanceTracker();
      t.apply(eq(Direction.outflow, 3000, 0, 0));
      expect(t.balanceOf(Provider.equity), isNull);
      t.apply(eq(Direction.inflow, 1000, 9000, 1));
      expect(t.balanceOf(Provider.equity), 900000);
    });
  });

  test('first message without a starting balance sets it, unchecked', () {
    final b = BalanceTracker();
    expect(b.apply(tx(Direction.outflow, 500, balance: 9000)), isNull);
    expect(b.balanceOf(Provider.mtn), 900000);
  });

  test('starting balance makes the very first message checked', () {
    final b = BalanceTracker()..setStarting(Provider.mtn, 1000000);
    final r = b.apply(tx(Direction.outflow, 500, fee: 20, balance: 9000)); // expected 9,480
    expect(r, isA<BalanceMismatch>());
    expect((r as BalanceMismatch).gap, -48000);
  });

  test('matching balance passes, and 1 RWF rounding is tolerated', () {
    final b = BalanceTracker()..setStarting(Provider.mtn, 1000000);
    expect(b.apply(tx(Direction.outflow, 500, fee: 20, balance: 9480)), isNull);
    expect(b.apply(tx(Direction.inflow, 100, balance: 9581)), isNull);
  });

  test('mismatch is flagged once, then the balance resets to the message', () {
    final b = BalanceTracker()..setStarting(Provider.mtn, 1000000);
    final r = b.apply(tx(Direction.outflow, 1000, balance: 8500)) as BalanceMismatch;
    expect([r.expected, r.actual, r.gap], [900000, 850000, -50000]);
    expect(b.balanceOf(Provider.mtn), 850000);
    expect(b.apply(tx(Direction.outflow, 500, balance: 8000)), isNull, reason: 'next check starts from the true figure');
  });

  test('messages without a balance only move the expected balance', () {
    final b = BalanceTracker()..setStarting(Provider.equity, 1000000);
    expect(b.apply(tx(Direction.outflow, 2000, p: Provider.equity)), isNull);
    expect(b.apply(tx(Direction.outflow, 3000, p: Provider.equity)), isNull);
    expect(b.apply(tx(Direction.inflow, 1000, balance: 6000, p: Provider.equity)), isNull);
  });

  test('one foreign card charge is resolved from the gap, not flagged', () {
    final b = BalanceTracker()..setStarting(Provider.equity, 10000000);
    final usd = tx(Direction.outflow, 20, currency: 'USD', p: Provider.equity);
    b.apply(usd);
    final r = b.apply(tx(Direction.inflow, 1000, balance: 71000, p: Provider.equity)); // 100,000 + 1,000 - 71,000
    expect(r, isA<ForeignChargeResolved>());
    expect((r as ForeignChargeResolved).rwfAmount, 3000000);
    expect(r.charge, same(usd));
  });

  test('several foreign charges give an approximate mismatch', () {
    final b = BalanceTracker()..setStarting(Provider.equity, 10000000);
    b.apply(tx(Direction.outflow, 20, currency: 'USD', p: Provider.equity));
    b.apply(tx(Direction.outflow, 9, currency: 'USD', p: Provider.equity));
    final r = b.apply(tx(Direction.inflow, 0, balance: 58000, p: Provider.equity));
    expect(r, isA<BalanceMismatch>());
    expect((r as BalanceMismatch).approximate, isTrue);
  });

  test('manual entries explaining a gap adjust the running balance', () {
    final b = BalanceTracker()..setStarting(Provider.mtn, 1000000);
    b.adjust(Provider.mtn, -50000);
    expect(b.apply(tx(Direction.outflow, 1000, balance: 8500)), isNull);
  });
}
