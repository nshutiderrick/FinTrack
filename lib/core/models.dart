/// Which account money moved in. Cash has no alerts; it only gets manual entries.
enum Provider { mtn, equity, airtel, cash }

extension ProviderName on Provider {
  String get label => switch (this) {
        Provider.equity => 'Equity Bank',
        Provider.mtn => 'MTN MoMo',
        Provider.airtel => 'Airtel Money',
        Provider.cash => 'Cash',
      };

  String get short => switch (this) {
        Provider.equity => 'Equity',
        Provider.mtn => 'MTN',
        Provider.airtel => 'Airtel',
        Provider.cash => 'Cash',
      };
}

/// What a message means for my money.
enum Kind {
  expense,
  income,
  transfer, // between my own accounts
  loanReceived,
  loanRepayment,
  loanInfo, // approval or closure notice, no money moves
  savings,
  cancel, // reversal of an earlier transaction
  failed, // kept only to flag subscriptions
  ignore,
  needsReview,
}

enum Direction { inflow, outflow, none }

/// One parsed alert. Money is in minor units (RWF 3,600 = 360000) so it never
/// suffers floating point errors.
class ParsedMessage {
  const ParsedMessage({
    required this.provider,
    required this.kind,
    required this.time,
    this.direction = Direction.none,
    this.amount = 0,
    this.currency = 'RWF',
    this.fee = 0,
    this.balance,
    this.counterparty,
    this.phone,
    this.isPerson = false,
    this.reference,
    this.loanId,
    this.categoryHint,
    this.note,
  });

  final Provider provider;
  final Kind kind;
  final DateTime time;
  final Direction direction;
  final int amount;
  final String currency;
  final int fee;

  /// Balance after this transaction, as written in the message (RWF minor units).
  final int? balance;
  final String? counterparty;

  /// Full number, or only the visible last digits when the message masks it.
  final String? phone;
  final bool isPerson;
  final String? reference;
  final String? loanId;
  final String? categoryHint;
  final String? note;

  /// False for USD/EUR card charges: the message gives no RWF amount.
  bool get rwfKnown => currency == 'RWF';

  /// Signed change to the account balance, fees included.
  int get balanceDelta => switch (direction) {
        Direction.inflow => amount,
        Direction.outflow => -(amount + fee),
        Direction.none => 0,
      };

  ParsedMessage copyWith({Kind? kind, Direction? direction, int? fee}) => ParsedMessage(
        provider: provider,
        kind: kind ?? this.kind,
        time: time,
        direction: direction ?? this.direction,
        amount: amount,
        currency: currency,
        fee: fee ?? this.fee,
        balance: balance,
        counterparty: counterparty,
        phone: phone,
        isPerson: isPerson,
        reference: reference,
        loanId: loanId,
        categoryHint: categoryHint,
        note: note,
      );

  /// Parsed fields only, for the cloud copy. Raw message text never goes here.
  Map<String, Object?> toMap() => {
        'provider': provider.name,
        'kind': kind.name,
        'time': time.millisecondsSinceEpoch,
        'direction': direction.name,
        'amount': amount,
        'currency': currency,
        'fee': fee,
        'balance': balance,
        'counterparty': counterparty,
        'phone': phone,
        'isPerson': isPerson,
        'reference': reference,
        'loanId': loanId,
        'categoryHint': categoryHint,
        'note': note,
      };

  static ParsedMessage fromMap(Map<String, Object?> m) => ParsedMessage(
        provider: Provider.values.byName(m['provider'] as String),
        kind: Kind.values.byName(m['kind'] as String),
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        direction: Direction.values.byName(m['direction'] as String? ?? 'none'),
        amount: m['amount'] as int? ?? 0,
        currency: m['currency'] as String? ?? 'RWF',
        fee: m['fee'] as int? ?? 0,
        balance: m['balance'] as int?,
        counterparty: m['counterparty'] as String?,
        phone: m['phone'] as String?,
        isPerson: m['isPerson'] as bool? ?? false,
        reference: m['reference'] as String?,
        loanId: m['loanId'] as String?,
        categoryHint: m['categoryHint'] as String?,
        note: m['note'] as String?,
      );

  @override
  String toString() =>
      'ParsedMessage($provider $kind $direction $amount $currency fee=$fee bal=$balance '
      '"$counterparty" phone=$phone ref=$reference)';
}

/// My own names and numbers, set once in Settings. Anything to or from these is
/// a transfer between my accounts, never income or spending.
class OwnIdentity {
  OwnIdentity({required List<String> names, required List<String> phones})
      : _names = names.map(_tokens).toList(),
        _phones = phones.map(_digits).toList();

  final List<Set<String>> _names;
  final List<String> _phones;

  /// Names match regardless of word order, case, extra spaces or repetition:
  /// "MUGABO  JEAN MUGABO JEAN" equals "Jean Mugabo".
  bool isOwnName(String? name) {
    if (name == null) return false;
    final t = _tokens(name);
    return t.isNotEmpty && _names.any((n) => n.length == t.length && n.containsAll(t));
  }

  /// Full numbers compare on their last 9 digits; masked ones ("0*****8726")
  /// on whatever trailing digits are visible, if at least 4. MTN shows only 3,
  /// which would match a stranger 1 time in 1,000, so MTN relies on the name.
  bool isOwnPhone(String? phone) {
    if (phone == null) return false;
    final visible = RegExp(r'(\d+)$').firstMatch(phone)?[1] ?? '';
    if (visible.length < 4) return false;
    final tail = visible.length > 9 ? visible.substring(visible.length - 9) : visible;
    return _phones.any((p) => p.endsWith(tail));
  }

  bool isOwn({String? name, String? phone}) => isOwnName(name) || isOwnPhone(phone);

  /// Two spellings of one name: same words, any order, case or repetition.
  static bool sameName(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = _tokens(a), y = _tokens(b);
    return x.length >= 2 && x.length == y.length && x.containsAll(y);
  }

  static Set<String> _tokens(String s) => s
      .toUpperCase()
      .split(RegExp(r'[^A-ZÀ-ſ]+'))
      .where((w) => w.isNotEmpty)
      .toSet();

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
}
