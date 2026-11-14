import 'categories.dart';
import 'ledger.dart';
import 'models.dart';

enum PeriodKind { day, week, month, year, custom }

/// A date range, start inclusive and end exclusive. Weeks run Monday to Sunday.
class Period {
  const Period(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start, end;

  factory Period.containing(PeriodKind kind, DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return switch (kind) {
      PeriodKind.day || PeriodKind.custom => Period(PeriodKind.day, day, _addDays(day, 1)),
      PeriodKind.week => () {
        final monday = _addDays(day, -(day.weekday - 1));
        return Period(kind, monday, _addDays(monday, 7));
      }(),
      PeriodKind.month => Period(kind, DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
      PeriodKind.year => Period(kind, DateTime(d.year), DateTime(d.year + 1)),
    };
  }

  /// [first] and [last] are both included.
  factory Period.custom(DateTime first, DateTime last) => Period(
    PeriodKind.custom,
    DateTime(first.year, first.month, first.day),
    _addDays(DateTime(last.year, last.month, last.day), 1),
  );

  /// The previous (-1) or next (+1) period of the same kind.
  Period shift(int n) => switch (kind) {
    PeriodKind.day => Period(kind, _addDays(start, n), _addDays(end, n)),
    PeriodKind.week => Period(kind, _addDays(start, 7 * n), _addDays(end, 7 * n)),
    PeriodKind.month => Period(kind, DateTime(start.year, start.month + n), DateTime(start.year, start.month + n + 1)),
    PeriodKind.year => Period(kind, DateTime(start.year + n), DateTime(start.year + n + 1)),
    PeriodKind.custom => () {
      final days = end.difference(start).inDays;
      return Period(kind, _addDays(start, days * n), _addDays(end, days * n));
    }(),
  };

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  String get label {
    final last = _addDays(end, -1);
    return switch (kind) {
      PeriodKind.day => '${_wd[start.weekday - 1]} ${start.day} ${_mo[start.month - 1]} ${start.year}',
      PeriodKind.week => '${start.day} ${_mo[start.month - 1]} – ${last.day} ${_mo[last.month - 1]} ${last.year}',
      PeriodKind.month => '${_moLong[start.month - 1]} ${start.year}',
      PeriodKind.year => '${start.year}',
      PeriodKind.custom =>
        '${start.day} ${_mo[start.month - 1]} ${start.year} – ${last.day} ${_mo[last.month - 1]} ${last.year}',
    };
  }

  /// Points for the trend chart: the days of the week for a day or a week,
  /// the weeks of the month for a month, the months of a year.
  List<(String, Period)> trend() {
    Period day(DateTime d) => Period(PeriodKind.day, d, _addDays(d, 1));
    switch (kind) {
      case PeriodKind.day || PeriodKind.week:
        final week = Period.containing(PeriodKind.week, start);
        return [for (var i = 0; i < 7; i++) ('${_wd[i]} ${_addDays(week.start, i).day}', day(_addDays(week.start, i)))];
      case PeriodKind.month:
        final out = <(String, Period)>[];
        var w = Period.containing(PeriodKind.week, start);
        while (w.start.isBefore(end)) {
          out.add(('${w.start.day} ${_mo[w.start.month - 1]}', w));
          w = w.shift(1);
        }
        return out;
      case PeriodKind.year:
        return [
          for (var m = 1; m <= 12; m++)
            (_mo[m - 1], Period(PeriodKind.month, DateTime(start.year, m), DateTime(start.year, m + 1))),
        ];
      case PeriodKind.custom:
        final days = end.difference(start).inDays;
        if (days <= 92) {
          return [
            for (var i = 0; i < days; i++)
              ('${_addDays(start, i).day} ${_mo[_addDays(start, i).month - 1]}', day(_addDays(start, i))),
          ];
        }
        final out = <(String, Period)>[];
        var m = Period.containing(PeriodKind.month, start);
        while (m.start.isBefore(end)) {
          out.add((_mo[m.start.month - 1], m));
          m = m.shift(1);
        }
        return out;
    }
  }

  // Calendar days, so a daylight-saving change never shifts a boundary.
  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _moLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

class CategoryTotal {
  CategoryTotal(this.name);
  final String name;
  int amount = 0;
  final List<Tx> txs = [];
}

class Totals {
  int income = 0, spent = 0;
  int pendingCount = 0, pendingAmount = 0;
  int movedIn = 0, movedOut = 0;
  int loansIn = 0, loansOut = 0;
  bool approximate = false;
  final Map<String, CategoryTotal> spending = {}, incomes = {};

  int get net => income - spent;

  void _add(Map<String, CategoryTotal> to, String name, int amount, Tx tx) {
    if (amount == 0) return;
    final c = to.putIfAbsent(name, () => CategoryTotal(name));
    c.amount += amount;
    if (!c.txs.contains(tx)) c.txs.add(tx);
  }

  /// Follows "What counts in the totals" in the spec. [scope] is the set of
  /// accounts being looked at; a transfer to or from an account outside it is
  /// money moved in or out (when all accounts are in scope, transfers vanish).
  void add(Tx t, {required Set<Provider> scope}) {
    final partial = scope.length < Provider.values.length;
    final pair = t.matched.pair?.message.provider;
    final movedAcross = partial && (pair == null || !scope.contains(pair));
    if (t.cancelled) return;
    final m = t.m;
    if (t.approximate && (t.isExpense || t.isIncome)) approximate = true;

    if (t.confirmed && t.isExpense) {
      spent += t.rwf;
      _add(spending, t.category!, t.rwf, t);
    } else if (t.confirmed && t.isIncome) {
      income += t.rwf;
      _add(incomes, t.category!, t.rwf, t);
    } else if (t.needsCategory) {
      pendingCount++;
      pendingAmount += t.rwf;
    } else if (t.kind == Kind.transfer && movedAcross) {
      // Not income or spending, but money did enter or leave the accounts in view.
      if (m.direction == Direction.inflow) movedIn += m.amount;
      if (m.direction == Direction.outflow) movedOut += m.amount;
    } else if (t.kind == Kind.loanReceived) {
      loansIn += m.amount;
    } else if (t.kind == Kind.loanRepayment) {
      loansOut += m.amount;
    }

    // Transfer fees and charges are spending even when the transfer is not.
    if (m.direction == Direction.outflow && m.fee > 0 && t.matched.movesMoney) {
      spent += m.fee;
      _add(spending, feesCategory, m.fee, t);
    }
  }

  List<CategoryTotal> get topSpending => spending.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  List<CategoryTotal> get topIncome => incomes.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
}

class AccountSummary {
  AccountSummary(this.provider, this.totals, this.closing);
  final Provider provider;
  final Totals totals;

  /// Balance at the end of the period, or null when no balance is known yet.
  final int? closing;
}

class Report {
  Report._(this.period, this.account, this.totals, this.byAccount, this.trend);

  final Period period;

  /// Null means all (visible) accounts.
  final Provider? account;
  final Totals totals;
  final List<AccountSummary> byAccount;
  final List<(String, Totals)> trend;

  static Totals totalsFor(Iterable<Tx> txs, Period p, Set<Provider> scope) {
    final t = Totals();
    for (final tx in txs) {
      if (!p.contains(tx.time)) continue;
      if (!scope.contains(tx.provider)) continue;
      t.add(tx, scope: scope);
    }
    return t;
  }

  /// [hidden] accounts are left out of every figure, as if they were not
  /// there; their transactions are still in [txs] and come back when shown.
  factory Report.build(List<Tx> txs, Period period, {Provider? account, Set<Provider> hidden = const {}}) {
    final scope = account != null ? {account} : Provider.values.where((p) => !hidden.contains(p)).toSet();
    final byAccount = <AccountSummary>[];
    for (final p in scope) {
      final own = txs.where((t) => t.provider == p).toList();
      final hasAny = own.any((t) => t.time.isBefore(period.end));
      if (!hasAny && account == null) continue;
      // txs are newest first, so the first one before the end is the last of the period.
      int? closing;
      for (final t in own) {
        if (t.time.isBefore(period.end) && t.balanceAfter != null) {
          closing = t.balanceAfter;
          break;
        }
      }
      byAccount.add(AccountSummary(p, totalsFor(own, period, {p}), closing));
    }
    return Report._(period, account, totalsFor(txs, period, scope), byAccount, [
      for (final (label, p) in period.trend()) (label, totalsFor(txs, p, scope)),
    ]);
  }
}
