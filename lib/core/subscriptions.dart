import 'ledger.dart';
import 'models.dart';

enum Cycle { weekly, monthly, yearly }

extension CycleText on Cycle {
  String get label => switch (this) {
        Cycle.weekly => 'Weekly',
        Cycle.monthly => 'Monthly',
        Cycle.yearly => 'Yearly',
      };

  DateTime after(DateTime d) => switch (this) {
        Cycle.weekly => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        Cycle.monthly => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        Cycle.yearly => DateTime(d.year + 1, d.month, d.day, d.hour, d.minute),
      };

  /// Share of one month, to add up the monthly cost.
  double get perMonth => switch (this) {
        Cycle.weekly => 52 / 12,
        Cycle.monthly => 1,
        Cycle.yearly => 1 / 12,
      };
}

enum SubStatus { active, cancelled, dismissed }

/// A subscription I confirmed, added by hand, or dismissed as not one.
/// Stored in users/{uid}/subscriptions/{id}.
class SubRecord {
  SubRecord({
    required this.id,
    required this.name,
    required this.key,
    required this.cycle,
    required this.status,
    this.amount,
    this.currency = 'RWF',
    this.account,
    this.firstRenewal,
  });

  final String id, name;

  /// Merchant key from [merchantKey]; empty for a manual one with no card charges.
  final String key;
  final Cycle cycle;
  final SubStatus status;
  final int? amount;
  final String currency;
  final Provider? account;

  /// Next renewal I typed in, for one with no payments found yet.
  final DateTime? firstRenewal;

  Map<String, Object?> toMap() => {
        'name': name,
        'key': key,
        'cycle': cycle.name,
        'status': status.name,
        'amount': amount,
        'currency': currency,
        'account': account?.name,
        'firstRenewal': firstRenewal?.millisecondsSinceEpoch,
      };

  static SubRecord fromMap(String id, Map<String, Object?> m) => SubRecord(
        id: id,
        name: m['name'] as String? ?? '',
        key: m['key'] as String? ?? '',
        cycle: Cycle.values.byName(m['cycle'] as String? ?? 'monthly'),
        status: SubStatus.values.byName(m['status'] as String? ?? 'active'),
        amount: m['amount'] as int?,
        currency: m['currency'] as String? ?? 'RWF',
        account: m['account'] == null ? null : Provider.values.byName(m['account'] as String),
        firstRenewal: m['firstRenewal'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['firstRenewal'] as int),
      );
}

/// "CLAUDE.AI SUBSCRIPTION" and "Claude.ai subscr" both give "CLAUDE".
String merchantKey(String? name) {
  const generic = {'THE', 'WWW', 'COM', 'PAY', 'PAYPAL', 'CARD', 'POS'};
  return (name ?? '')
      .toUpperCase()
      .split(RegExp(r'[^A-Z0-9]+'))
      .firstWhere((w) => w.length >= 3 && !generic.contains(w) && !RegExp(r'^\d+$').hasMatch(w), orElse: () => '');
}

class Subscription {
  Subscription({required this.name, required this.key, required this.cycle, this.record});

  final String name, key;
  final Cycle cycle;
  final SubRecord? record;

  /// Oldest first.
  final List<Tx> payments = [];
  final List<Tx> failures = [];

  bool get suggested => record == null;
  SubStatus get status => record?.status ?? SubStatus.active;

  Tx? get last => payments.isEmpty ? null : payments.last;
  DateTime? get lastPaid => last?.time;
  String get currency => last?.m.currency ?? record?.currency ?? 'RWF';

  /// Amount in the charge's own currency (USD charges stay in USD).
  int? get amount => last?.m.amount ?? record?.amount;

  /// RWF cost of one renewal, when known.
  int? get rwf {
    final t = last;
    if (t != null && !t.approximate) return t.rwf;
    return currency == 'RWF' ? record?.amount : null;
  }

  DateTime? get nextRenewal {
    final p = lastPaid;
    if (p == null) return record?.firstRenewal;
    return cycle.after(p);
  }

  /// A charge failed after the last successful one (card had no money).
  bool get failedRecently => failures.any((f) => lastPaid == null || f.time.isAfter(lastPaid!));

  /// The renewal date passed a few days ago with no payment.
  bool missed(DateTime now) {
    final n = nextRenewal;
    return status == SubStatus.active && n != null && now.isAfter(n.add(const Duration(days: 3)));
  }
}

class SubscriptionBook {
  SubscriptionBook._(this.active, this.suggestions, this.cancelled);

  final List<Subscription> active, suggestions, cancelled;

  /// RWF per month for active subscriptions whose RWF cost is known.
  int get monthlyRwf => active.fold(0, (s, x) => s + ((x.rwf ?? 0) * x.cycle.perMonth).round());
  int get yearlyRwf => monthlyRwf * 12;
  bool get costApproximate => active.any((x) => x.rwf == null);

  /// Card charges and other merchant payments; never people or transfers.
  static bool _isCharge(Tx t) =>
      !t.cancelled && t.isExpense && !t.m.isPerson && t.m.counterparty != null && t.provider != Provider.cash;

  /// Typical gap between charges, if it looks like a renewal cycle.
  static Cycle? _cycleOf(List<Tx> asc) {
    if (asc.length < 2) return null;
    final gaps = [for (var i = 1; i < asc.length; i++) asc[i].time.difference(asc[i - 1].time).inDays]..sort();
    final median = gaps[gaps.length ~/ 2];
    if (median >= 6 && median <= 8) return Cycle.weekly;
    if (median >= 26 && median <= 35) return Cycle.monthly;
    if (median >= 350 && median <= 380) return Cycle.yearly;
    return null;
  }

  factory SubscriptionBook.build(List<Tx> txs, List<SubRecord> records) {
    final asc = [...txs]..sort((a, b) => a.time.compareTo(b.time));
    final charges = <String, List<Tx>>{};
    final failed = <String, List<Tx>>{};
    for (final t in asc) {
      final key = merchantKey(t.m.counterparty);
      if (key.isEmpty) continue;
      if (_isCharge(t)) charges.putIfAbsent(key, () => []).add(t);
      if (t.kind == Kind.failed) failed.putIfAbsent(key, () => []).add(t);
    }

    final active = <Subscription>[], suggestions = <Subscription>[], cancelled = <Subscription>[];
    final known = <String>{};
    for (final r in records) {
      if (r.key.isNotEmpty) known.add(r.key);
      if (r.status == SubStatus.dismissed) continue;
      final s = Subscription(name: r.name, key: r.key, cycle: r.cycle, record: r)
        ..payments.addAll(charges[r.key] ?? const [])
        ..failures.addAll(failed[r.key] ?? const []);
      (r.status == SubStatus.active ? active : cancelled).add(s);
    }
    charges.forEach((key, list) {
      if (known.contains(key)) return;
      // Same merchant, about the same amount, on a regular cycle.
      final sameAmount = list.where((t) => t.m.currency == list.last.m.currency).toList();
      final cycle = _cycleOf(sameAmount);
      if (cycle == null) return;
      suggestions.add(Subscription(name: list.last.m.counterparty!, key: key, cycle: cycle)
        ..payments.addAll(sameAmount)
        ..failures.addAll(failed[key] ?? const []));
    });

    int soonest(Subscription a, Subscription b) =>
        (a.nextRenewal ?? DateTime(9999)).compareTo(b.nextRenewal ?? DateTime(9999));
    return SubscriptionBook._(active..sort(soonest), suggestions..sort(soonest), cancelled);
  }
}
