/// The kinds of account I can add as mine during setup. The Equity card is not
/// here on purpose: its number is never stored (only the last 4 digits ever
/// appear in alerts), and it is not needed to spot transfers.
enum AccountType { mtn, airtel, equity }

extension AccountTypeText on AccountType {
  String get label => switch (this) {
        AccountType.mtn => 'MTN MoMo number',
        AccountType.airtel => 'Airtel Money number',
        AccountType.equity => 'Equity account number',
      };

  String get hint => switch (this) {
        AccountType.mtn => '078 or 079…',
        AccountType.airtel => '072 or 073…',
        AccountType.equity => '13 digits',
      };

  /// A light check, so a typo is caught without rejecting real numbers.
  String? check(String number) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return 'Enter the number';
    return switch (this) {
      AccountType.mtn || AccountType.airtel when d.length < 9 => 'A phone number has at least 9 digits',
      AccountType.equity when d.length < 10 => 'An account number has at least 10 digits',
      _ => null,
    };
  }
}

/// MTN numbers start 078 or 079 and Airtel 072 or 073 (with or without 250).
/// Null when the number is masked, too short or from another network.
AccountType? accountTypeOfPhone(String number) {
  final d = number.replaceAll(RegExp(r'\D'), '');
  if (d.length < 9) return null;
  final local = d.substring(d.length - 9); // 7XXXXXXXX
  if (RegExp(r'^7[89]').hasMatch(local)) return AccountType.mtn;
  if (RegExp(r'^7[23]').hasMatch(local)) return AccountType.airtel;
  return null;
}

/// One of my own accounts, saved in my private profile.
class OwnAccount {
  const OwnAccount(this.type, this.number);

  final AccountType type;

  /// Digits only.
  final String number;

  Map<String, Object?> toMap() => {'type': type.name, 'number': number};

  static OwnAccount? fromMap(Object? m) {
    if (m is! Map) return null;
    final type = AccountType.values.asNameMap()[m['type']];
    final number = m['number'];
    if (type == null || number is! String || number.isEmpty) return null;
    return OwnAccount(type, number);
  }
}
