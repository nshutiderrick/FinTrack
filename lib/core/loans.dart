import 'ledger.dart';
import 'models.dart';

enum LoanSide { iOwe, owedToMe }

/// A loan I added by hand, or created with "I lent this". Stored in
/// users/{uid}/loans/{id}; transactions point to it with their `loanLink`.
class LoanRecord {
  LoanRecord({
    required this.id,
    required this.side,
    required this.person,
    required this.amount,
    required this.createdAt,
    this.totalToRepay,
    this.due,
    this.note,
    this.closed = false,
  });

  final String id;
  final LoanSide side;
  final String person;
  final int amount;
  final int? totalToRepay;
  final DateTime createdAt;
  final DateTime? due;
  final String? note;
  final bool closed;

  Map<String, Object?> toMap() => {
        'side': side.name,
        'person': person,
        'amount': amount,
        'totalToRepay': totalToRepay,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'due': due?.millisecondsSinceEpoch,
        'note': note,
        'closed': closed,
      };

  static LoanRecord fromMap(String id, Map<String, Object?> m) => LoanRecord(
        id: id,
        side: LoanSide.values.byName(m['side'] as String),
        person: m['person'] as String? ?? '',
        amount: m['amount'] as int? ?? 0,
        totalToRepay: m['totalToRepay'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int? ?? 0),
        due: m['due'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due'] as int),
        note: m['note'] as String?,
        closed: m['closed'] as bool? ?? false,
      );
}

class Loan {
  Loan({
    required this.id,
    required this.side,
    required this.who,
    required this.borrowed,
    required this.openedAt,
    this.totalToRepay,
    this.due,
    this.note,
    this.record,
    this.closedByMessage = false,
  });

  final String id;
  final LoanSide side;

  /// Lender for money I owe, borrower for money owed to me.
  final String who;
  int borrowed;
  final int? totalToRepay;
  final DateTime openedAt;
  final DateTime? due;
  final String? note;

  /// Set for loans I added by hand; null for app loans built from messages.
  final LoanRecord? record;
  bool closedByMessage;

  /// The transaction that moved the borrowed money, when there is one.
  Tx? source;
  final List<Tx> payments = [];

  bool get fromApp => record == null;
  int get repaid => payments.fold(0, (s, t) => s + t.rwf);

  /// What is still to pay. Unknown for an open app loan, whose interest only
  /// shows once it closes.
  int? get left {
    if (closed) return 0;
    final total = totalToRepay ?? (fromApp ? null : borrowed);
    return total == null ? null : (total - repaid).clamp(0, total);
  }

  bool get closed {
    if (closedByMessage || (record?.closed ?? false)) return true;
    final total = totalToRepay ?? (fromApp ? null : borrowed);
    return total != null && total > 0 && repaid >= total;
  }

  bool overdue(DateTime now) => !closed && due != null && now.isAfter(due!);
}

/// Money I owe and money owed to me (spec: Loans).
class LoanBook {
  LoanBook._(this.iOwe, this.owedToMe, this.unlinked);

  final List<Loan> iOwe, owedToMe;

  /// Repayments the app could not tie to a loan.
  final List<Tx> unlinked;

  Loan? byId(String id) => [...iOwe, ...owedToMe].where((l) => l.id == id).firstOrNull;

  List<Loan> get open => [...iOwe, ...owedToMe].where((l) => !l.closed).toList();

  int totalLeft(LoanSide side) => (side == LoanSide.iOwe ? iOwe : owedToMe)
      .where((l) => !l.closed)
      .fold(0, (s, l) => s + (l.left ?? (l.borrowed - l.repaid).clamp(0, l.borrowed)));

  int overdueCount(DateTime now) => open.where((l) => l.overdue(now)).length;

  static String _lender(String? name) =>
      (name ?? '').toUpperCase().split(RegExp(r'[^A-Z]+')).firstWhere((w) => w.length >= 3, orElse: () => '');

  factory LoanBook.build(List<Tx> txs, List<LoanRecord> records) {
    final asc = txs.where((t) => !t.cancelled).toList()..sort((a, b) => a.time.compareTo(b.time));
    final byLoanId = <String, Loan>{};
    final iOwe = <Loan>[];
    final unlinked = <Tx>[];

    Loan appLoan(String id, Tx t) {
      final l = Loan(id: id, side: LoanSide.iOwe, who: t.m.counterparty ?? 'Loan', borrowed: t.m.amount, openedAt: t.time);
      iOwe.add(l);
      return l;
    }

    for (final t in asc) {
      final m = t.m;
      if (t.record.loanLink != null) continue; // a loan I manage by hand
      switch (t.kind) {
        case Kind.loanInfo when m.loanId != null:
          final loan = byLoanId[m.loanId!] ??= appLoan('app:${m.loanId}', t);
          if (m.note == 'closed') loan.closedByMessage = true;
        case Kind.loanReceived:
          // "You have received X RWF from MoFaya Loans" has no id: it pairs with
          // the approval of the same amount a few minutes before.
          final approval = iOwe.where((l) =>
              l.source == null &&
              l.borrowed == m.amount &&
              t.time.difference(l.openedAt).abs() <= const Duration(minutes: 10));
          final loan = approval.isEmpty ? appLoan('app:rx:${t.id}', t) : approval.first;
          loan.source = t;
        case Kind.loanRepayment:
          Loan? loan = m.loanId == null ? null : byLoanId[m.loanId!];
          if (loan == null) {
            final lender = _lender(m.counterparty);
            final open = iOwe.where((l) => !l.closed && lender.isNotEmpty && _lender(l.who) == lender);
            loan = open.isEmpty ? null : open.first;
          }
          loan == null ? unlinked.add(t) : loan.payments.add(t);
        default:
      }
    }

    final owedToMe = <Loan>[];
    final manual = <String, Loan>{};
    for (final r in records) {
      final l = Loan(
        id: r.id,
        side: r.side,
        who: r.person,
        borrowed: r.amount,
        totalToRepay: r.totalToRepay,
        openedAt: r.createdAt,
        due: r.due,
        note: r.note,
        record: r,
      );
      manual[r.id] = l;
      (r.side == LoanSide.iOwe ? iOwe : owedToMe).add(l);
    }
    for (final t in asc) {
      final l = manual[t.record.loanLink];
      if (l == null) continue;
      // Money owed to me goes out once and comes back in parts; a loan I owe the other way round.
      final isSource = (l.side == LoanSide.owedToMe) == (t.m.direction == Direction.outflow);
      if (isSource && l.source == null) {
        l.source = t;
      } else {
        l.payments.add(t);
      }
    }

    int newestFirst(Loan a, Loan b) => b.openedAt.compareTo(a.openedAt);
    return LoanBook._(iOwe..sort(newestFirst), owedToMe..sort(newestFirst), unlinked);
  }
}
