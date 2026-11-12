import 'ledger.dart';
import 'models.dart';

enum TxSort { dateDesc, dateAsc, amountDesc, amountAsc, nameAsc, nameDesc }

extension TxSortText on TxSort {
  String get label => switch (this) {
        TxSort.dateDesc => 'Newest first',
        TxSort.dateAsc => 'Oldest first',
        TxSort.amountDesc => 'Amount: high to low',
        TxSort.amountAsc => 'Amount: low to high',
        TxSort.nameAsc => 'Name: A to Z',
        TxSort.nameDesc => 'Name: Z to A',
      };
}

/// Filter groups that are not categories but are asked for the same way.
const transfersGroup = 'Between my accounts';
const pendingGroup = 'No category yet';
const loansGroup = 'Loans';

/// The group a transaction is filtered under: its category, or one of the
/// groups above. Null for things that are not money in or out (notices).
String? txGroup(Tx t) {
  if (t.isLoan || t.kind == Kind.loanReceived || t.kind == Kind.loanRepayment) return loansGroup;
  if (t.kind == Kind.transfer || t.kind == Kind.savings) return transfersGroup;
  if (t.isExpense || t.isIncome || t.kind == Kind.needsReview) return t.category ?? pendingGroup;
  return null;
}

/// The transactions list: every expense, income and transfer, sorted and
/// filtered. An empty [groups] means no category filter.
List<Tx> queryTxs(
  Iterable<Tx> txs, {
  TxSort sort = TxSort.dateDesc,
  Set<String> groups = const {},
  bool Function(Provider)? account,
  String search = '',
}) {
  final q = search.trim().toUpperCase();
  final out = txs.where((t) {
    if (t.m.direction == Direction.none) return false;
    final g = txGroup(t);
    if (g == null) return false;
    if (groups.isNotEmpty && !groups.contains(g)) return false;
    if (account != null && !account(t.provider)) return false;
    if (q.isNotEmpty && !t.title.toUpperCase().contains(q) && !(t.record.description?.toUpperCase().contains(q) ?? false)) {
      return false;
    }
    return true;
  }).toList();

  int byDate(Tx a, Tx b) => a.time.compareTo(b.time);
  int byAmount(Tx a, Tx b) => a.rwf.compareTo(b.rwf);
  int byName(Tx a, Tx b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  out.sort(switch (sort) {
    TxSort.dateDesc => (a, b) => byDate(b, a),
    TxSort.dateAsc => byDate,
    TxSort.amountDesc => (a, b) => byAmount(b, a) != 0 ? byAmount(b, a) : byDate(b, a),
    TxSort.amountAsc => (a, b) => byAmount(a, b) != 0 ? byAmount(a, b) : byDate(b, a),
    TxSort.nameAsc => (a, b) => byName(a, b) != 0 ? byName(a, b) : byDate(b, a),
    TxSort.nameDesc => (a, b) => byName(b, a) != 0 ? byName(b, a) : byDate(b, a),
  });
  return out;
}

/// Every group present in [txs], categories first in my order, then the extras.
List<String> groupsIn(Iterable<Tx> txs, List<String> categoryOrder) {
  final present = {for (final t in txs) ?txGroup(t)};
  return [
    ...categoryOrder.where(present.contains),
    ...present.where((g) => !categoryOrder.contains(g) && g != transfersGroup && g != pendingGroup && g != loansGroup).toList()..sort(),
    for (final g in const [pendingGroup, transfersGroup, loansGroup])
      if (present.contains(g)) g,
  ];
}
