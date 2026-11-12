import 'models.dart';

/// Turns one bank or mobile-money alert into a [ParsedMessage].
/// Rules follow "Parsing Rules" in the project spec. It never guesses: anything
/// it cannot read with confidence comes back as [Kind.needsReview].
///
/// Duplicates (same reference) and transfer pairs are matched later, not here.
class MessageParser {
  MessageParser(this.me);

  final OwnIdentity me;

  /// Returns null for senders the app does not track.
  ParsedMessage? parse(String sender, String body, DateTime receivedAt) {
    final b = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return switch (sender) {
      'M-Money' => _mtn(b, receivedAt),
      'EQUITYBANK' => _equity(b, receivedAt),
      'AirtelMoney' => _airtel(b, receivedAt),
      _ => null,
    };
  }

  // ---------------------------------------------------------------- MTN

  ParsedMessage _mtn(String b, DateTime rx) {
    final time = _isoTime(b) ?? rx;
    ParsedMessage msg(Kind kind,
            {Direction direction = Direction.none,
            int amount = 0,
            int fee = 0,
            String? counterparty,
            String? phone,
            bool isPerson = false,
            String? loanId,
            String? categoryHint,
            String? note,
            bool withBalance = true}) =>
        ParsedMessage(
          provider: Provider.mtn,
          kind: kind,
          time: time,
          direction: direction,
          amount: amount,
          fee: fee,
          balance: withBalance ? _mtnBalance(b) : null,
          counterparty: counterparty,
          phone: phone,
          isPerson: isPerson,
          reference: _first(b, r'(?:TxId|TransactionId|FT Id|Financial Transaction Id)\s*:?\s*(\d+)',
              caseSensitive: false),
          loanId: loanId,
          categoryHint: categoryHint,
          note: note,
        );

    if (b.contains('one-time password')) return msg(Kind.ignore, withBalance: false);
    if (RegExp('failed', caseSensitive: false).hasMatch(b)) {
      return msg(Kind.failed, withBalance: false);
    }
    if (b.contains("K'Avance") || b.contains('overdraft')) return msg(Kind.ignore, withBalance: false);

    RegExpMatch? x;

    // Loans: approval and closure are notices; the money moves in separate messages.
    if ((x = _m(b, r'loan application of ([\d,]+) RWF with id (\d+) .*?for (.+?) has been')) != null) {
      return msg(Kind.loanInfo,
          amount: _money(x![1]!), loanId: x[2], counterparty: x[3], note: 'approved', withBalance: false);
    }
    if (b.contains('preapproval')) return msg(Kind.ignore, withBalance: false);
    if ((x = _m(b, r'Your loan (.+?) with id (\d+) of ([\d,]+) RWF has been closed')) != null) {
      return msg(Kind.loanInfo,
          amount: _money(x![3]!), loanId: x[2], counterparty: x[1], note: 'closed', withBalance: false);
    }
    // "Your repayment of X" and "X RWF has been used to pay your loan" share one
    // Financial Transaction Id, so the duplicate check keeps only one of them.
    if ((x = _m(b, r'Your repayment of ([\d,]+) RWF for loan id (\d+) to (.+?) has been')) != null) {
      return msg(Kind.loanRepayment,
          direction: Direction.outflow, amount: _money(x![1]!), loanId: x[2], counterparty: x[3]);
    }
    if ((x = _m(b, r'([\d,]+) RWF has been used to pay your loan')) != null) {
      return msg(Kind.loanRepayment, direction: Direction.outflow, amount: _money(x![1]!));
    }

    // Person-to-person send (three wordings over the years).
    if ((x = _m(b, r'([\d,]+) RWF transferred to (.+?) \((\d+)\)')) != null) {
      final name = _clean(x![2]!), phone = x[3]!;
      final fee = _money(_first(b, r'Fee(?: was)?\s*:\s*([\d,]+)\s*RWF') ?? '0');
      final own = me.isOwn(name: name, phone: phone);
      return msg(own ? Kind.transfer : Kind.expense,
          direction: Direction.outflow,
          amount: _money(x[1]!),
          fee: fee,
          counterparty: name,
          phone: phone,
          isPerson: !own);
    }

    // Payments: merchants, pay codes, airtime, savings, and sends to bank accounts.
    if ((x = _m(b, r'Your payment of ([\d,]+) RWF to (.+?)(?: with token.*?)? (?:was completed|has been completed|SUCCESSFUL)')) !=
        null) {
      final amount = _money(x![1]!);
      final fee = _money(_first(b, r'Fee\s*:?\s*([\d,]+)\s*RWF') ?? '0');
      final payee = _clean(x[2]!);
      ParsedMessage out(Kind k, {String? who, bool person = false, String? hint}) => msg(k,
          direction: Direction.outflow, amount: amount, fee: fee, counterparty: who, isPerson: person, categoryHint: hint);

      if (payee.startsWith('Mokash Savings')) return out(Kind.savings, who: 'Mokash Savings');
      if (payee.startsWith('Mokash Loan')) return out(Kind.loanRepayment, who: 'Mokash Loan');
      if (payee == 'Airtime') return out(Kind.expense, who: 'MTN Airtime', hint: 'Airtime');
      if (payee == 'eKash') return out(Kind.transfer, who: 'eKash');
      final bank = RegExp(r'^(.+?) at EQUITY BANK').firstMatch(payee);
      if (bank != null) {
        final name = bank[1]!;
        return me.isOwnName(name) ? out(Kind.transfer, who: name) : out(Kind.expense, who: name, person: true);
      }
      if (payee.startsWith('EQUITY BANK')) return out(Kind.needsReview, who: payee); // no name: mine or not?
      if (me.isOwnName(payee)) return out(Kind.transfer, who: payee);
      // "SAWA CITI LTD. 919324": strip the merchant code.
      final merchant = RegExp(r'^(.*?)[.\s]+\d+$').firstMatch(payee)?[1] ?? payee;
      return out(Kind.expense, who: merchant);
    }

    if ((x = _m(b, r'A transaction of ([\d,]+) RWF by (.+?) was completed')) != null) {
      final biller = _clean(x![2]!);
      final hint = biller.contains('Bundle') || biller.contains('Voice Pack') ? 'Data and voice bundles' : null;
      return msg(Kind.expense,
          direction: Direction.outflow,
          amount: _money(x[1]!),
          fee: _money(_first(b, r'Fee\s*:?\s*([\d,]+)\s*RWF') ?? '0'),
          counterparty: biller,
          categoryHint: hint);
    }

    if ((x = _m(b, r'You have received ([\d,]+) RWF from (.+?) \(\**(\d+)\)')) != null) {
      final amount = _money(x![1]!);
      final name = _clean(x[2]!).replaceAll(RegExp(r'[\s.]+$'), '');
      final last = x[3]!;
      final fromMsg = _first(b, r'Message from sender: (.*?)\.\s*(?:Balance|Your new balance)');
      ParsedMessage inn(Kind k, {String? who, bool person = false}) =>
          msg(k, direction: Direction.inflow, amount: amount, counterparty: who, phone: last, isPerson: person);

      if (RegExp('loan', caseSensitive: false).hasMatch(name)) return inn(Kind.loanReceived, who: name);
      final viaEquity = fromMsg != null && (fromMsg.contains('Equity B2C') || fromMsg.contains('FSP:EquityBank'));
      if (viaEquity || me.isOwn(name: name, phone: last)) return inn(Kind.transfer, who: name);
      // Money from abroad: the company is only the courier, the person is in the sender message.
      if (RegExp(r'THUNES|Onafriq|ECOBANK').hasMatch(name) && fromMsg != null && fromMsg.isNotEmpty) {
        return inn(Kind.income, who: _clean(fromMsg), person: true);
      }
      return inn(Kind.income, who: name, person: true);
    }

    if ((x = _m(b, r'withdrawn ([\d,]+) RWF')) != null) {
      return msg(Kind.expense,
          direction: Direction.outflow,
          amount: _money(x![1]!),
          fee: _money(_first(b, r'Fee(?: paid)?\s*:\s*([\d,]+)') ?? '0'),
          counterparty: _first(b, r'via agent: (.+?) [(-]')?.trim(),
          categoryHint: 'Cash withdrawal');
    }

    return msg(Kind.needsReview, withBalance: false);
  }

  int? _mtnBalance(String b) {
    final s = _first(b, r'(?:new balance|Balance)\s*:?\s*([\d,]+)\s*RWF', caseSensitive: false);
    return s == null ? null : _money(s);
  }

  // ------------------------------------------------------------- Equity

  ParsedMessage _equity(String b, DateTime rx) {
    ParsedMessage msg(Kind kind,
            {Direction direction = Direction.none,
            int amount = 0,
            String currency = 'RWF',
            int fee = 0,
            int? balance,
            String? counterparty,
            String? phone,
            bool isPerson = false,
            String? reference,
            String? categoryHint,
            DateTime? time}) =>
        ParsedMessage(
          provider: Provider.equity,
          kind: kind,
          time: time ?? rx,
          direction: direction,
          amount: amount,
          currency: currency,
          fee: fee,
          balance: balance,
          counterparty: counterparty,
          phone: phone,
          isPerson: isPerson,
          reference: reference,
          categoryHint: categoryHint,
        );

    if (b.startsWith('Munyamuryango') || b.startsWith('Banyamuryango')) return msg(Kind.ignore);
    if (b.startsWith('Confirmed.') || b.contains('Debit for card')) return msg(Kind.ignore);

    RegExpMatch? x;

    // Card messages: the date inside is unreliable, so they keep the arrival time.
    // Amounts may have a space as thousands separator: "RWF 2 000.00".
    if ((x = _m(b, r'Auth Reversal for card .*?Amt:\s*([A-Z]{3})\s*(\d[\d., ]*)\s*Details:\s*(.+?)\s+\.')) != null) {
      return msg(Kind.cancel,
          direction: Direction.inflow, currency: x![1]!, amount: _money(x[2]!), counterparty: x[3]);
    }
    if ((x = _m(b, r'Auth for card .*?Amt:\s*([A-Z]{3})\s*(\d[\d., ]*)\s*Details:\s*(.+?)\s+\.')) != null) {
      // No reference in card alerts; the bank's own timestamp identifies a resent copy.
      final stamp = _first(b, r'Date:\s*(\S+ \S+)');
      return msg(Kind.expense,
          direction: Direction.outflow,
          currency: x![1]!,
          amount: _money(x[2]!),
          counterparty: x[3],
          reference: stamp == null ? null : 'AUTH $stamp');
    }
    if ((x = _m(b, r'transaction to merchant (.+?) for ([A-Z]{3}) ([\d.,]+) has failed')) != null) {
      return msg(Kind.failed, counterparty: x![1], currency: x[2]!, amount: _money(x[3]!));
    }

    final balance = _equityMoney(b, r'(?:Balance:?|new balance is|balance)\s*[}\s]*(?:RWF\s*)?([\d.,]*\d)');
    final ref = _first(b, r'Ref\.?:?\s*(\w+)', caseSensitive: false);

    if ((x = _m(b, r'([\d.,]+) RWF (?:has been|was) successfully sent to\s*(.*?)\s*([\d*]{6,})')) != null) {
      final name = _clean(x![2]!);
      final phone = x[3]!;
      final fee = (_equityMoney(b, r'Charges\s*(?:RWF\s*)?([\d.,]*\d)') ?? 0) +
          (_equityMoney(b, r'SMS alert charge RWF\}?\s*([\d.,]*\d)') ?? 0);
      final own = me.isOwn(name: name.isEmpty ? null : name, phone: phone);
      return msg(own ? Kind.transfer : Kind.expense,
          direction: Direction.outflow,
          amount: _money(x[1]!),
          fee: fee,
          balance: balance,
          counterparty: name.isEmpty ? null : name,
          phone: phone,
          isPerson: !own,
          reference: ref,
          time: _equityTime(b) ?? rx);
    }

    if ((x = _m(b, r'You have just received RWF ([\d.,]+)(?: from (.+?) [\d*]{6,})?')) != null ||
        (x = _m(b, r'You have received RWF ([\d.,]+) ON \S+ via incoming transfer\s+from (.+?) On:')) != null ||
        (x = _m(b, r'You have received ([\d.,]+) RWF from (.+?) [\d*]{6,} to your Equity account')) != null ||
        (x = _m(b, r'credited with RWF ([\d.,]+)()')) != null) {
      final name = x![2] == null || x[2]!.isEmpty ? null : _clean(x[2]!);
      final own = me.isOwnName(name);
      return msg(own ? Kind.transfer : Kind.income,
          direction: Direction.inflow,
          amount: _money(x[1]!),
          balance: balance,
          counterparty: name,
          isPerson: name != null && !own,
          reference: _first(b, r'REF:?\s+(\S+?),?\s', caseSensitive: false) ?? ref);
    }

    if ((x = _m(b, r'airtime purchase of ([\d.,]+) RWF')) != null) {
      return msg(Kind.expense,
          direction: Direction.outflow,
          amount: _money(x![1]!),
          fee: (_equityMoney(b, r'Charges\s*(?:RWF\s*)?([\d.,]*\d)') ?? 0) +
              (_equityMoney(b, r'SMS alert charge RWF\}?\s*([\d.,]*\d)') ?? 0),
          balance: balance,
          counterparty: 'Airtel airtime',
          reference: ref,
          categoryHint: 'Airtime');
    }

    // Reversals give the money back and cancel the matching earlier send.
    if ((x = _m(b, r'reversal of ([\d.,]+) RWF to account')) != null ||
        (x = _m(b, r'transfer of RWF ([\d.,]+) .*?could not be completed')) != null) {
      return msg(Kind.cancel,
          direction: Direction.inflow,
          amount: _money(x![1]!),
          reference: _first(b, r'Ref\.\s*(\w+)'));
    }

    // Notices, surveys, OTPs: ignore. Anything else that mentions money: ask me.
    final mentionsMoney = RegExp(r'RWF\s*[\d,]+|[\d,.]+\s*RWF').hasMatch(b);
    return msg(mentionsMoney && !b.startsWith('Dear Member') ? Kind.needsReview : Kind.ignore);
  }

  int? _equityMoney(String b, String pattern) {
    final s = _first(b, pattern, caseSensitive: false);
    return s == null ? null : _money(s);
  }

  // ------------------------------------------------------------- Airtel

  ParsedMessage _airtel(String b, DateTime rx) {
    final ref = _first(b, r'(?:TID|Txn ID|TXN ID)[:\s(]*([A-Z]{2}\d{6}\.\d{4}\.[A-Z]\d{5})');
    final time = _airtelTime(ref) ?? rx;
    ParsedMessage msg(Kind kind,
            {Direction direction = Direction.none,
            int amount = 0,
            int fee = 0,
            int? balance,
            String? counterparty,
            String? phone,
            bool isPerson = false,
            String? categoryHint}) =>
        ParsedMessage(
          provider: Provider.airtel,
          kind: kind,
          time: time,
          direction: direction,
          amount: amount,
          fee: fee,
          balance: balance,
          counterparty: counterparty,
          phone: phone,
          isPerson: isPerson,
          reference: ref,
          categoryHint: categoryHint,
        );
    int? bal(String pattern) {
      final s = _first(b, pattern, caseSensitive: false);
      return s == null ? null : _money(s);
    }

    if (RegExp(r'ntibyakunze|Transaction Failed').hasMatch(b)) return msg(Kind.failed);
    if (RegExp(r'PIN|ibitaribyo').hasMatch(b)) return msg(Kind.ignore);

    RegExpMatch? x;
    if ((x = _m(b, r'You have received RWF ([\d,]+) from (.+?) (\d{9,12}) in MTN')) != null) {
      final name = _clean(x![2]!), phone = x[3]!;
      final own = me.isOwn(name: name, phone: phone);
      return msg(own ? Kind.transfer : Kind.income,
          direction: Direction.inflow,
          amount: _money(x[1]!),
          balance: bal(r'NEW BALANCE is\s*RWF\s*([\d,]+)'),
          counterparty: name,
          phone: phone,
          isPerson: !own);
    }
    if ((x = _m(b, r'Kugura Inite ya Rwf ([\d,]+)')) != null) {
      return msg(Kind.expense,
          direction: Direction.outflow,
          amount: _money(x![1]!),
          balance: bal(r'mufite Rwf ([\d,]+)'),
          counterparty: 'Airtel airtime',
          categoryHint: 'Airtime');
    }
    if ((x = _m(b, r'Kugura Pack ya Rwf ([\d,]+)')) != null) {
      return msg(Kind.expense,
          direction: Direction.outflow,
          amount: _money(x![1]!),
          balance: bal(r'mufite Rwf ([\d,]+)'),
          counterparty: 'Airtel bundle',
          categoryHint: 'Data and voice bundles');
    }
    if ((x = _m(b, r'Kohereza Rwf ([\d,]+) kuri (.+?) (\d{9,12}) muri')) != null) {
      final name = _clean(x![2]!), phone = x[3]!;
      final own = me.isOwn(name: name, phone: phone);
      return msg(own ? Kind.transfer : Kind.expense,
          direction: Direction.outflow,
          amount: _money(x[1]!),
          fee: _money(_first(b, r'IGICIRO cya serivisi Rwf ([\d,]+)') ?? '0'),
          balance: bal(r'Usigaranye Rwf ([\d,]+)'),
          counterparty: name,
          phone: phone,
          isPerson: !own);
    }
    if ((x = _m(b, r'Kwishyura RWF\s*([\d,]+) kuri (.+?) byagenze')) != null) {
      final payee = _clean(x![2]!);
      // "E Kash App Kode N" is how Airtel sends my money on to my own accounts
      // (seen arriving on MoMo seconds later), like MTN's "payment to eKash":
      // a transfer, which the matcher pairs with the money arriving.
      final toEkash = RegExp(r'^E ?Kash\b', caseSensitive: false).hasMatch(payee);
      return msg(toEkash ? Kind.transfer : Kind.expense,
          direction: Direction.outflow,
          amount: _money(x[1]!),
          balance: bal(r'Ubu mufite RWF\s*([\d,]+)'),
          counterparty: toEkash ? 'eKash' : payee);
    }
    return msg(Kind.needsReview);
  }

  // ------------------------------------------------------------ helpers

  static RegExpMatch? _m(String b, String pattern) => RegExp(pattern).firstMatch(b);

  static String? _first(String b, String pattern, {bool caseSensitive = true}) =>
      RegExp(pattern, caseSensitive: caseSensitive).firstMatch(b)?[1];

  /// "3,600", "2 000.00", "4000", "300000.0" -> minor units.
  static int _money(String s) => (double.parse(s.replaceAll(RegExp(r'[,\s]'), '')) * 100).round();

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// "2026-11-10 17:21:33" or "2026-11-04T20:53:45.902+02:00".
  static DateTime? _isoTime(String b) {
    final s = _first(b, r'(\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:\.\d+)?(?:[+-]\d\d:\d\d)?)');
    final t = s == null ? null : DateTime.tryParse(s);
    return t != null && t.isUtc ? t.toLocal() : t;
  }

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  /// "on 07/11/2026 at 12:49", "on 20/10/26 at 13:42:21", "on 02 Sep 2026 at 20:06".
  static DateTime? _equityTime(String b) {
    var x = RegExp(r'on (\d\d)/(\d\d)/(\d{2,4}) at (\d\d):(\d\d)').firstMatch(b);
    if (x != null) {
      final y = int.parse(x[3]!);
      return DateTime(y < 100 ? 2000 + y : y, int.parse(x[2]!), int.parse(x[1]!), int.parse(x[4]!), int.parse(x[5]!));
    }
    x = RegExp(r'on (\d\d) ([A-Za-z]{3}) (\d{4}) at (\d\d):(\d\d)').firstMatch(b);
    if (x != null) {
      final m = _months.indexOf(x[2]!.toLowerCase()) + 1;
      if (m > 0) return DateTime(int.parse(x[3]!), m, int.parse(x[1]!), int.parse(x[4]!), int.parse(x[5]!));
    }
    return null;
  }

  /// Airtel ids encode the time: "MP261107.1432.D04933" = 2026-11-07 14:32.
  static DateTime? _airtelTime(String? ref) {
    final x = ref == null ? null : RegExp(r'^[A-Z]{2}(\d\d)(\d\d)(\d\d)\.(\d\d)(\d\d)').firstMatch(ref);
    if (x == null) return null;
    return DateTime(2000 + int.parse(x[1]!), int.parse(x[2]!), int.parse(x[3]!), int.parse(x[4]!), int.parse(x[5]!));
  }
}
