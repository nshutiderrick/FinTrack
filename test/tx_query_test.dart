import 'package:expense_tracker/core/ledger.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/tx_query.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 11, 1, 9);
var _n = 0;

TxRecord rec(Kind kind, Direction dir, int rwf, String who, {int day = 0, String? category, Provider p = Provider.mtn}) => TxRecord(
      id: 'r${_n++}',
      source: TxSource.alert,
      category: category,
      message: ParsedMessage(
        provider: p,
        kind: kind,
        direction: dir,
        time: t0.add(Duration(days: day)),
        amount: rwf * 100,
        counterparty: who,
        reference: 'x${_n++}',
      ),
    );

void main() {
  final txs = Ledger.build([
    rec(Kind.expense, Direction.outflow, 3000, 'Bakery', day: 0, category: 'Food and drinks'),
    rec(Kind.expense, Direction.outflow, 12000, 'Arena', day: 1, category: 'Entertainment'),
    rec(Kind.income, Direction.inflow, 50000, 'Client', day: 2, category: 'Salary'),
    rec(Kind.expense, Direction.outflow, 700, 'Corner shop', day: 3), // no category yet
    rec(Kind.transfer, Direction.outflow, 9000, 'eKash', day: 4, p: Provider.equity),
    rec(Kind.loanInfo, Direction.none, 1000, 'MoFaya', day: 5), // a notice, not money
  ]).txs;

  test('lists expenses, income and transfers, not notices', () {
    final all = queryTxs(txs);
    expect(all.map((t) => t.title), ['eKash', 'Corner shop', 'Client', 'Arena', 'Bakery']);
  });

  test('sorts by date, amount and name both ways', () {
    expect(queryTxs(txs, sort: TxSort.dateAsc).first.title, 'Bakery');
    expect(queryTxs(txs, sort: TxSort.amountDesc).first.title, 'Client');
    expect(queryTxs(txs, sort: TxSort.amountAsc).first.title, 'Corner shop');
    expect(queryTxs(txs, sort: TxSort.nameAsc).map((t) => t.title).first, 'Arena');
    expect(queryTxs(txs, sort: TxSort.nameDesc).map((t) => t.title).first, 'eKash');
  });

  test('filters by one or more categories, including transfers and uncategorised', () {
    expect(queryTxs(txs, groups: {'Food and drinks'}).single.title, 'Bakery');
    expect(queryTxs(txs, groups: {'Salary', 'Entertainment'}).map((t) => t.title), ['Client', 'Arena']);
    expect(queryTxs(txs, groups: {transfersGroup}).single.title, 'eKash');
    expect(queryTxs(txs, groups: {pendingGroup}).single.title, 'Corner shop');
  });

  test('filters by account and search', () {
    expect(queryTxs(txs, account: (p) => p == Provider.equity).single.title, 'eKash');
    expect(queryTxs(txs, search: 'bak').single.title, 'Bakery');
  });

  test('the category list keeps my order and adds the extra groups last', () {
    expect(groupsIn(txs, ['Salary', 'Food and drinks', 'Entertainment', 'Transport']),
        ['Salary', 'Food and drinks', 'Entertainment', pendingGroup, transfersGroup]);
  });
}
