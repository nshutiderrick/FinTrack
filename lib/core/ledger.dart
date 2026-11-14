import 'balance.dart';
import 'matcher.dart';
import 'models.dart';

enum TxSource { alert, statement, manual }

/// One stored transaction: the parsed fields plus what I decided about it.
/// Decisions live in their own fields, so re-parsing an alert never wipes them.
class TxRecord {
  TxRecord({
    required this.id,
    required this.source,
    required this.message,
    this.category,
    this.description,
    this.kindOverride,
    this.accepted = false,
    this.loanLink,
    this.photoUrl,
    this.photoId,
    this.rwfAmount,
    this.feeOverride,
  });

  /// The full fee a statement showed (charges and SMS charge folded in), when
  /// the alert showed less. Replaces the alert's fee; never added to it.
  final int? feeOverride;

  final String id;
  final TxSource source;
  final ParsedMessage message;
  final String? category;
  final String? description;

  /// What I said a "Needs review" item really is.
  final Kind? kindOverride;

  /// I accepted the balance gap shown on this message as is.
  final bool accepted;

  /// The loan this money belongs to (lent, borrowed or repaid). Such money is
  /// neither spending nor income.
  final String? loanLink;

  /// Cloudinary photo of the receipt or item.
  final String? photoUrl, photoId;

  /// RWF cost of a foreign card charge, from a statement.
  final int? rwfAmount;

  Map<String, Object?> parsedMap() => {...message.toMap(), 'source': source.name};

  static TxRecord fromMap(String id, Map<String, Object?> m) => TxRecord(
        id: id,
        source: TxSource.values.byName(m['source'] as String? ?? 'alert'),
        message: ParsedMessage.fromMap(m),
        category: m['category'] as String?,
        description: m['description'] as String?,
        kindOverride: m['kindOverride'] == null ? null : Kind.values.byName(m['kindOverride'] as String),
        accepted: m['accepted'] as bool? ?? false,
        loanLink: m['loanLink'] as String?,
        photoUrl: m['photoUrl'] as String?,
        photoId: m['photoId'] as String?,
        rwfAmount: m['rwfAmount'] as int?,
        feeOverride: m['feeOverride'] as int?,
      );

  TxRecord withMessage(ParsedMessage m) => TxRecord(
        id: id,
        source: source,
        message: m,
        category: category,
        description: description,
        kindOverride: kindOverride,
        accepted: accepted,
        loanLink: loanLink,
        photoUrl: photoUrl,
        photoId: photoId,
        rwfAmount: rwfAmount,
        feeOverride: feeOverride,
      );
}

/// A transaction as the app shows it, after matching and the balance check.
class Tx {
  Tx(this.record, this.matched);

  final TxRecord record;
  final Matched matched;

  /// RWF cost of a foreign card charge, worked out from the balance gap.
  int? resolvedRwf;

  /// The account's running balance right after this transaction.
  int? balanceAfter;

  /// The message's balance was a placeholder (Equity's 0) and was not used.
  bool balanceNotShown = false;

  String get id => record.id;
  ParsedMessage get m => matched.message;
  Kind get kind => matched.kind;
  bool get cancelled => matched.cancelled;
  String? get category => record.category;
  Provider get provider => m.provider;
  DateTime get time => m.time;

  bool get isExpense => kind == Kind.expense;
  bool get isIncome => kind == Kind.income;

  /// Lent, borrowed or repaid: tracked under Loans instead.
  bool get isLoan => record.loanLink != null;

  /// Waiting for me to pick a category (spec: Pending and Category Flow).
  bool get needsCategory => !cancelled && !isLoan && (isExpense || isIncome) && category == null;

  /// The parser could not tell what this is.
  bool get needsKind => !cancelled && kind == Kind.needsReview;

  /// Counted in the income and spending totals.
  bool get confirmed => !cancelled && !isLoan && (isExpense || isIncome) && category != null;

  /// RWF cost of a foreign charge: from a statement, else from the balance gap.
  int? get foreignRwf => record.rwfAmount ?? resolvedRwf;

  /// Amount in RWF, or 0 while a foreign charge's RWF cost is still unknown.
  int get rwf => m.rwfKnown ? m.amount : (foreignRwf ?? 0);
  bool get approximate => !m.rwfKnown && foreignRwf == null;

  /// Display name of the other side.
  String get title => m.counterparty ?? m.categoryHint ?? _kindLabel(kind);

  static String _kindLabel(Kind k) => switch (k) {
        Kind.transfer => 'Transfer between my accounts',
        Kind.loanReceived => 'Loan received',
        Kind.loanRepayment => 'Loan repayment',
        Kind.savings => 'Savings',
        Kind.cancel => 'Reversal',
        Kind.income => 'Money received',
        Kind.expense => 'Payment',
        _ => 'Unknown message',
      };
}

/// A message balance that did not match the expected balance.
class Mismatch {
  Mismatch(this.tx, this.outcome);
  final Tx tx;
  final BalanceMismatch outcome;

  Provider get provider => outcome.provider;
  int get gap => outcome.gap;
  bool get accepted => tx.record.accepted;
}

class AccountBalance {
  const AccountBalance(this.balance, this.asOf);
  final int balance;

  /// When the last message showing a real balance arrived.
  final DateTime asOf;
}

/// Everything the screens need, worked out from the stored records.
/// It is rebuilt from scratch on every change, so a fix (a category, a manual
/// entry dated before a gap) flows through matching and the balance check.
class Ledger {
  Ledger._(this.txs, this.mismatches, this.balances, this.learnedNames);

  /// Newest first.
  final List<Tx> txs;
  final List<Mismatch> mismatches;
  final Map<Provider, AccountBalance> balances;

  /// Names both sides of a transfer used, so they are almost surely mine.
  final Set<String> learnedNames;

  static final empty = Ledger._(const [], const [], const {}, const {});

  List<Mismatch> get openMismatches => mismatches.where((x) => !x.accepted).toList();
  List<Tx> get pending => txs.where((t) => t.needsCategory).toList();
  List<Tx> get unknown => txs.where((t) => t.needsKind).toList();
  int get reviewCount => pending.length + unknown.length + openMismatches.length;

  factory Ledger.build(Iterable<TxRecord> records, {Map<Provider, int> starting = const {}}) {
    final byOrigin = Map<ParsedMessage, TxRecord>.identity();
    final messages = <ParsedMessage>[];
    for (final r in records) {
      final m = r.message.copyWith(kind: r.kindOverride, fee: r.feeOverride);
      byOrigin[m] = r;
      messages.add(m);
    }

    final matcher = TransactionMatcher();
    final matched = matcher.match(messages);
    final tracker = BalanceTracker();
    starting.forEach(tracker.setStarting);
    // Cash has no alerts: its balance is the sum of the entries added by hand.
    if (!starting.containsKey(Provider.cash)) tracker.setStarting(Provider.cash, 0);

    final txs = <Tx>[];
    final mismatches = <Mismatch>[];
    final lastReal = <Provider, DateTime>{};

    for (final t in matched) {
      final tx = Tx(byOrigin[t.origin]!, t);
      txs.add(tx);

      if (t.movesMoney || t.message.balance != null) {
        // Something that moved no money may still show the balance: check it only.
        final input = t.movesMoney ? t.message : t.message.copyWith(direction: Direction.none);
        final outcome = tracker.apply(input);
        switch (outcome) {
          case BalanceMismatch():
            mismatches.add(Mismatch(tx, outcome));
          case ForeignChargeResolved(:final charge, :final rwfAmount):
            final chargeTx = txs.lastWhere((x) => identical(x.m, charge) || identical(x.matched.origin, charge),
                orElse: () => tx);
            chargeTx.resolvedRwf = rwfAmount;
          case null:
        }
      }
      if (tracker.lastShowedBalance || (t.message.provider == Provider.cash && t.movesMoney)) {
        lastReal[t.message.provider] = t.message.time;
      } else if (t.message.balance != null) {
        tx.balanceNotShown = true; // Equity's placeholder 0
      }
      tx.balanceAfter = tracker.balanceOf(t.message.provider);
    }

    final balances = <Provider, AccountBalance>{
      for (final p in Provider.values)
        if (tracker.balanceOf(p) != null && lastReal[p] != null) p: AccountBalance(tracker.balanceOf(p)!, lastReal[p]!),
    };
    return Ledger._(txs.reversed.toList(), mismatches.reversed.toList(), balances, matcher.learnedNames);
  }
}
