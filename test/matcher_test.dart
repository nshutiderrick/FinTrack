import 'package:expense_tracker/core/matcher.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 11, 4, 20, 53, 45);

ParsedMessage msg(Provider p, Kind k, Direction d, int rwf,
        {Duration at = Duration.zero,
        String? ref,
        String? who,
        bool person = false,
        int? balance,
        String currency = 'RWF'}) =>
    ParsedMessage(
      provider: p,
      kind: k,
      time: t0.add(at),
      direction: d,
      amount: rwf * 100,
      currency: currency,
      reference: ref,
      counterparty: who,
      isPerson: person,
      balance: balance == null ? null : balance * 100,
    );

void main() {
  final matcher = TransactionMatcher();

  test('a resent alert with the same reference is dropped, even hours later', () {
    final r = matcher.match([
      msg(Provider.equity, Kind.expense, Direction.outflow, 1000, ref: 'AH4Z', who: 'Alice M.', person: true),
      msg(Provider.equity, Kind.expense, Direction.outflow, 1000,
          ref: 'AH4Z', who: 'Alice M.', person: true, at: const Duration(hours: 9)),
    ]);
    expect(r, hasLength(1));
  });

  test('the same reference on two providers is not a duplicate', () {
    final r = matcher.match([
      msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, ref: '123'),
      msg(Provider.airtel, Kind.expense, Direction.outflow, 1000, ref: '123'),
    ]);
    expect(r, hasLength(2));
  });

  test('loan repayment pair merges and keeps the balance', () {
    final r = matcher.match([
      msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 87200, ref: '3158', who: 'MoFaya'),
      msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 87200, ref: '3158', balance: 17523),
    ]);
    expect(r, hasLength(1));
    expect(r.single.message.balance, 1752300);
    expect(r.single.message.counterparty, 'MoFaya');
    expect(r.single.inTotals, isFalse);
  });

  test('Airtel send and payment with one id keep the named person', () {
    final r = matcher.match([
      msg(Provider.airtel, Kind.expense, Direction.outflow, 190000, ref: 'MP1', who: 'E Kash App', balance: 4980),
      msg(Provider.airtel, Kind.expense, Direction.outflow, 190000, ref: 'MP1', who: 'Irène U.', person: true),
    ]);
    expect(r.single.message.counterparty, 'Irène U.');
    expect(r.single.message.balance, 498000);
  });

  test('token payment with no name pairs with the Equity receipt as a transfer', () {
    final r = matcher.match([
      msg(Provider.mtn, Kind.needsReview, Direction.outflow, 4000, who: 'EQUITY BANK RWANDA'),
      msg(Provider.equity, Kind.income, Direction.inflow, 4000, at: const Duration(seconds: -4)),
    ]);
    expect(r.map((t) => t.kind), everyElement(Kind.transfer));
    expect(r.first.pair, same(r.last));
    expect(r.any((t) => t.inTotals), isFalse);
  });

  test('a receive from a named person is never taken as a transfer', () {
    final r = matcher.match([
      msg(Provider.mtn, Kind.needsReview, Direction.outflow, 4000),
      msg(Provider.airtel, Kind.income, Direction.inflow, 4000, who: 'Alice M.', person: true, at: const Duration(seconds: 3)),
    ]);
    expect(r.map((t) => t.kind), [Kind.needsReview, Kind.income]);
  });

  test('sides too far apart, or on the same provider, are not paired', () {
    final far = matcher.match([
      msg(Provider.mtn, Kind.transfer, Direction.outflow, 4000),
      msg(Provider.airtel, Kind.transfer, Direction.inflow, 4000, at: const Duration(minutes: 5)),
    ]);
    expect(far.every((t) => t.pair == null), isTrue);
    final same = matcher.match([
      msg(Provider.mtn, Kind.transfer, Direction.outflow, 4000),
      msg(Provider.mtn, Kind.transfer, Direction.inflow, 4000, at: const Duration(seconds: 5)),
    ]);
    expect(same.every((t) => t.pair == null), isTrue);
  });

  test('reversal with a reference cancels that send', () {
    final r = matcher.match([
      msg(Provider.equity, Kind.transfer, Direction.outflow, 4000, ref: 'AV2R'),
      msg(Provider.equity, Kind.cancel, Direction.inflow, 4000, ref: 'AV2R', at: const Duration(hours: 12)),
    ]);
    expect(r.first.cancelled, isTrue);
    expect(r.first.inTotals, isFalse);
    expect(r.first.movesMoney, isTrue, reason: 'the balance check still sees both');
  });

  test('a reversal with nothing to cancel does not move the balance', () {
    final r = matcher.match([msg(Provider.equity, Kind.cancel, Direction.inflow, 4000, ref: 'X')]);
    expect(r.single.movesMoney, isFalse);
  });

  test('card auth reversal cancels the matching merchant charge only', () {
    final r = matcher.match([
      msg(Provider.equity, Kind.expense, Direction.outflow, 1, currency: 'EUR', who: 'ORACLE IRELAND', ref: 'AUTH a'),
      msg(Provider.equity, Kind.expense, Direction.outflow, 1, currency: 'EUR', who: 'OTHER SHOP', ref: 'AUTH b',
          at: const Duration(minutes: 1)),
      msg(Provider.equity, Kind.cancel, Direction.inflow, 1, currency: 'EUR', who: 'ORACLE IRELAND',
          at: const Duration(minutes: 5)),
    ]);
    expect(r[0].cancelled, isTrue);
    expect(r[1].cancelled, isFalse);
  });

  test('output is sorted by transaction time', () {
    final r = matcher.match([
      msg(Provider.mtn, Kind.expense, Direction.outflow, 2, at: const Duration(minutes: 2)),
      msg(Provider.mtn, Kind.expense, Direction.outflow, 1),
    ]);
    expect(r.map((t) => t.message.amount), [100, 200]);
  });
}
