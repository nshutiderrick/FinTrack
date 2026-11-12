import '../core/categories.dart' as defaults;
import '../core/matcher.dart';
import '../core/models.dart';
import '../core/parser.dart';
import '../platform/alerts.dart';

/// What the app tells the pop-up, kept on the phone: my identity (to spot
/// transfers between my accounts), my categories, and what I picked before.
class PopupConfig {
  const PopupConfig({
    this.names = const [],
    this.phones = const [],
    this.expenseCategories = defaults.expenseCategories,
    this.incomeCategories = defaults.incomeCategories,
    this.lastCategoryByPayee = const {},
    this.topExpense = const [],
    this.topIncome = const [],
  });

  final List<String> names, phones, expenseCategories, incomeCategories;

  /// Upper-cased payee to the category I gave it last time.
  final Map<String, String> lastCategoryByPayee;

  /// My most used categories, most used first.
  final List<String> topExpense, topIncome;

  Map<String, Object?> toMap() => {
        'names': names,
        'phones': phones,
        'expenseCategories': expenseCategories,
        'incomeCategories': incomeCategories,
        'lastCategoryByPayee': lastCategoryByPayee,
        'topExpense': topExpense,
        'topIncome': topIncome,
      };

  static List<String> _list(Object? v, List<String> fallback) {
    final l = v is List ? v.whereType<String>().toList() : null;
    return l == null || l.isEmpty ? fallback : l;
  }

  static PopupConfig fromMap(Map<String, Object?> m) => PopupConfig(
        names: _list(m['names'], const []),
        phones: _list(m['phones'], const []),
        expenseCategories: _list(m['expenseCategories'], defaults.expenseCategories),
        incomeCategories: _list(m['incomeCategories'], defaults.incomeCategories),
        lastCategoryByPayee: {
          for (final e in ((m['lastCategoryByPayee'] as Map?) ?? const {}).entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
        },
        topExpense: _list(m['topExpense'], const []),
        topIncome: _list(m['topIncome'], const []),
      );
}

/// One pop-up to show: a new expense or income that needs a category.
class PopupItem {
  const PopupItem({
    required this.alertId,
    required this.title,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.income,
    required this.isPerson,
    required this.time,
    required this.categories,
    required this.suggested,
  });

  final String alertId, title, currency;
  final Provider provider;
  final int amount;
  final bool income, isPerson;
  final DateTime time;

  /// All categories, the likely ones first.
  final List<String> categories;

  /// Up to 2 most likely categories, for the notification buttons.
  final List<String> suggested;

  Map<String, Object?> toMap() => {
        'alertId': alertId,
        'title': title,
        'provider': provider.name,
        'providerLabel': provider.label,
        'amount': amount,
        'currency': currency,
        'income': income,
        'isPerson': isPerson,
        'time': time.millisecondsSinceEpoch,
        'categories': categories,
        'suggested': suggested,
      };
}

/// Alerts older than this are not news (Android replays them when the
/// listener reconnects), so they never pop up.
const popupMaxAge = Duration(minutes: 15);

/// Decides whether [alert] needs a category pop-up. [recent] are the other
/// alerts the phone has seen lately, so a send that is half of a transfer
/// between my accounts (the other half arrived seconds later) stays quiet,
/// and a repeat of an alert already seen is ignored.
PopupItem? evaluatePopup(RawAlert alert, List<RawAlert> recent, PopupConfig config, {DateTime? now}) {
  if ((now ?? DateTime.now()).difference(alert.postedAt) > popupMaxAge) return null;
  final parser = MessageParser(OwnIdentity(names: config.names, phones: config.phones));
  final byId = <String, ParsedMessage>{};
  for (final a in [...recent, alert]) {
    final sender = a.sender;
    if (sender == null) continue;
    final m = parser.parse(sender, a.text, a.postedAt);
    if (m == null || m.kind == Kind.ignore) continue;
    byId[a.id] = m;
  }
  final mine = byId[alert.id];
  if (mine == null) return null;

  final matched = TransactionMatcher().match(byId.values);
  final t = matched.where((x) => identical(x.origin, mine)).firstOrNull;
  // Not there: it was folded into an earlier copy of the same alert.
  if (t == null || t.cancelled) return null;
  if (t.kind != Kind.expense && t.kind != Kind.income) return null;

  final m = t.message;
  final income = t.kind == Kind.income;
  final all = income ? config.incomeCategories : config.expenseCategories;
  final payee = m.counterparty?.toUpperCase().trim();
  final likely = <String>[
    if (payee != null && config.lastCategoryByPayee[payee] != null) config.lastCategoryByPayee[payee]!,
    if (!income) ?defaults.suggestedCategory(m.categoryHint),
    ...(income ? config.topIncome : config.topExpense),
  ].where(all.contains).toSet().toList();

  return PopupItem(
    alertId: alert.id,
    title: m.counterparty ?? m.categoryHint ?? (income ? 'Money received' : 'Payment'),
    provider: m.provider,
    amount: m.amount,
    currency: m.currency,
    income: income,
    isPerson: m.isPerson,
    time: m.time,
    categories: [...likely, ...all.where((c) => !likely.contains(c))],
    suggested: likely.take(2).toList().isEmpty ? all.take(2).toList() : likely.take(2).toList(),
  );
}
