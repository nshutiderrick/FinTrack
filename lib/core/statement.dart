import 'models.dart';

/// One row of an MTN MoMo or Equity Bank statement.
class StatementRow {
  const StatementRow({
    required this.provider,
    required this.time,
    required this.hasTime,
    required this.direction,
    required this.amount,
    required this.balance,
    required this.description,
    required this.refs,
    this.fee = 0,
    this.counterparty,
    this.phone,
    this.type,
    this.txnRef,
    this.details = '',
    this.balanceKnown = true,
  });

  /// False when the statement's Balance column cannot be used to check my
  /// balance: Equity lists newest first but adds the column up from the top,
  /// so it is not the balance after each transaction.
  final bool balanceKnown;

  /// Equity's numeric "Transaction Ref" (newer layout). A transaction and its
  /// charge rows share it.
  final String? txnRef;

  /// Every text line of the row, joined (to find a parent's reference inside a
  /// charge row, as in "SMS CHARGE …KN8DMSC").
  final String details;

  StatementRow withFee(int extra) => StatementRow(
        provider: provider,
        time: time,
        hasTime: hasTime,
        direction: direction,
        amount: amount,
        balance: balance,
        description: description,
        refs: refs,
        fee: fee + extra,
        counterparty: counterparty,
        phone: phone,
        type: type,
        txnRef: txnRef,
        details: details,
        balanceKnown: balanceKnown,
      );

  StatementRow withoutBalance() => StatementRow(
        provider: provider,
        time: time,
        hasTime: hasTime,
        direction: direction,
        amount: amount,
        balance: balance,
        description: description,
        refs: refs,
        fee: fee,
        counterparty: counterparty,
        phone: phone,
        type: type,
        txnRef: txnRef,
        details: details,
        balanceKnown: false,
      );

  final Provider provider;

  /// MoMo rows have a time; Equity rows only a value date (midnight).
  final DateTime time;
  final bool hasTime;
  final Direction direction;

  /// RWF minor units, like [ParsedMessage].
  final int amount, fee, balance;
  final String description;

  /// Every id on the row: MoMo transaction id; Equity MTN ref (A…), eKash ref
  /// (S…) and MoMo transaction id inside TPGYBILL lines.
  final Set<String> refs;
  final String? counterparty, phone;

  /// MoMo transaction type (TRANSFER, PAYMENT, CUSTOM_PAYMENT, DEBIT, CASH_IN).
  final String? type;

  @override
  String toString() => 'StatementRow(${provider.name} $time ${direction.name} ${amount ~/ 100} bal=${balance ~/ 100} '
      '"$counterparty" refs=$refs)';
}

/// A fee belongs to its transaction (spec: Statement Import, "Fees"). Equity
/// books one transfer as several rows: the amount, a charge row with the same
/// Transaction Ref and description, and an "SMS CHARGE" row whose reference is
/// the transfer's plus "SC". Each charge row is folded into its transaction as
/// its fee, so matching sees one transaction, like the alert ("Charges RWF 20,
/// SMS alert charge RWF 4"), and no fee is counted twice. A charge with no
/// transaction of its own (a monthly fee) stays a row and is added once.
List<StatementRow> foldFees(List<StatementRow> rows) {
  final charges = RegExp(r'\b(SMS CHARGE|CHARGES?|COMMISSION|FEES?|EXCISE|LEVY)\b', caseSensitive: false);
  bool sameDay(StatementRow a, StatementRow b) =>
      a.time.year == b.time.year && a.time.month == b.time.month && a.time.day == b.time.day;
  bool belongsTo(StatementRow c, StatementRow p) {
    if (identical(c, p) || c.direction != Direction.outflow || p.direction != Direction.outflow) return false;
    if (c.provider != p.provider || c.amount >= p.amount) return false;
    if (charges.hasMatch(p.description)) return false; // a parent is a real transaction
    // "SMS CHARGE" carries the parent's reference with a suffix; Equity
    // sometimes books it the next day, so a day apart is allowed for it.
    final smsLinked = charges.hasMatch(c.description) && p.refs.any((r) => c.details.contains(r));
    if (smsLinked) return c.time.difference(p.time).inDays.abs() <= 1;
    if (!sameDay(c, p)) return false;
    // Same Transaction Ref: the transfer's own charge row. (Not merely the same
    // description: two card payments at one shop on one day are two payments.)
    if (c.txnRef != null && c.txnRef == p.txnRef) return true;
    // Older rows have no Transaction Ref, but the charge row carries the
    // transfer's own reference (A…, S…).
    return c.refs.isNotEmpty && c.refs.any(p.refs.contains);
  }

  final feeOf = Map<StatementRow, int>.identity();
  final folded = Set<StatementRow>.identity();
  for (final c in rows) {
    final parents = rows.where((p) => belongsTo(c, p)).toList();
    if (parents.isEmpty) continue;
    // The biggest same-day candidate is the transaction itself.
    final parent = parents.reduce((a, b) => a.amount >= b.amount ? a : b);
    feeOf[parent] = (feeOf[parent] ?? 0) + c.amount;
    folded.add(c);
  }
  return [
    for (final r in rows)
      if (!folded.contains(r)) feeOf[r] == null ? r : r.withFee(feeOf[r]!),
  ];
}

/// Rows on or after the day [since] falls on. Equity rows carry only a date, so
/// the comparison is by day: a row from the install day itself is kept.
List<StatementRow> rowsSince(List<StatementRow> rows, DateTime since) {
  final day = DateTime(since.year, since.month, since.day);
  return rows.where((r) => !r.time.isBefore(day)).toList();
}

/// Reads statement text (as extracted from the PDF, one text line per line).
class StatementParser {
  /// Picks the format from the first lines. Returns null for anything else.
  static List<StatementRow>? parse(List<String> raw) {
    // Windows line endings would hide the bare values the parsers look for.
    final lines = [for (final l in raw) l.endsWith('\r') ? l.substring(0, l.length - 1) : l];
    final head = lines.take(40).join('\n');
    if (head.contains('Momo Statement')) return momo(lines);
    if (head.contains('Account Statement') || (head.contains('Account Number') && head.contains('Value Date'))) {
      return equity(lines);
    }
    return null;
  }

  // -------------------------------------------------------------- MoMo

  static final _momoId = RegExp(r'^\d{9,13}$');
  static final _momoStatus = RegExp(r'^(SUCCESSFUL|FAILED|PENDING|REVERSED)');
  static final _momoTime = RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$');

  static List<StatementRow> momo(List<String> lines) {
    final own = RegExp(r'Number:\s*(\d+)').firstMatch(lines.take(20).join('\n'))?[1];
    final rows = <StatementRow>[];
    for (var i = 0; i + 3 < lines.length; i++) {
      if (!_momoId.hasMatch(lines[i].trim()) || !_momoStatus.hasMatch(lines[i + 1].trim())) continue;
      if (!_momoTime.hasMatch(lines[i + 3].trim())) continue;
      final id = lines[i].trim(), status = lines[i + 1].trim(), type = lines[i + 2].trim();
      // Amount, fee and balance are the first three values in a row after the parties.
      // A party number is followed by a name, so it never starts such a run.
      var j = i + 4;
      while (j + 2 < lines.length &&
          !(RegExp(r'^\d+$').hasMatch(lines[j].trim()) &&
              RegExp(r'^(\d+|N/A)$').hasMatch(lines[j + 1].trim()) &&
              RegExp(r'^-?\d+$').hasMatch(lines[j + 2].trim()))) {
        j++;
      }
      if (j + 2 >= lines.length) break;
      if (status != 'SUCCESSFUL') continue;

      // Party lines: number or merchant code (digits, or a lowercase code like "rndps"),
      // then the name (capitalised, may wrap). Does not rely on trailing spaces, which
      // some PDF readers drop.
      final parties = lines.sublist(i + 4, j).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final isIdLine = RegExp(r'^(\d{4,}|[a-z][a-z0-9_]*)$');
      final toAt = parties.indexWhere(isIdLine.hasMatch, 1);
      final fromId = parties.isEmpty ? '' : parties.first.trim();
      final fromName = toAt < 0 ? '' : _dedupe(parties.sublist(1, toAt).join(' '));
      final toId = toAt < 0 ? '' : parties[toAt].trim();
      final toName = toAt < 0 ? '' : _dedupe(parties.sublist(toAt + 1).join(' '));
      final out = own != null && fromId == own;
      rows.add(StatementRow(
        provider: Provider.mtn,
        time: DateTime.parse(lines[i + 3].trim()),
        hasTime: true,
        direction: out ? Direction.outflow : Direction.inflow,
        amount: int.parse(lines[j].trim()) * 100,
        fee: lines[j + 1].trim() == 'N/A' ? 0 : int.parse(lines[j + 1].trim()) * 100,
        balance: int.parse(lines[j + 2].trim()) * 100,
        description: '$type ${out ? 'to $toName' : 'from $fromName'}',
        refs: {id},
        counterparty: out ? toName : fromName,
        phone: out ? toId : fromId,
        type: type,
      ));
      i = j + 2;
    }
    return rows;
  }

  /// "SAWA CITI LTD. SAWA CITI LTD." -> "SAWA CITI LTD.", "Thomas Thomas" -> "Thomas".
  static String _dedupe(String s) {
    final words = s.trim().split(RegExp(r'\s+'));
    if (words.length.isEven) {
      final half = words.length ~/ 2;
      if (words.sublist(0, half).join(' ') == words.sublist(half).join(' ')) return words.sublist(0, half).join(' ');
    }
    return words.join(' ');
  }

  // ------------------------------------------------------------ Equity

  static final _date = RegExp(r'^(\d\d)/(\d\d)/(\d{4})$');
  static final _money = RegExp(r'^-?[\d,]+\.\d\d$');
  static final _noise = RegExp(
      r'^(#PAGE|Transaction Details|Payment reference|Value Date|Credit \(Money In\)|Debit \(Money Out\)|Balance|Total|Transactions|Disclaimer|inforwanda|\d\d/\d\d/\d{4}\s+Page)');

  static int _rwf(String s) => (double.parse(s.replaceAll(',', '')) * 100).round();

  static List<StatementRow> equity(List<String> lines) {
    // Opening balance = closing - credits + debits, from the "Total" line at the end.
    int? opening;
    final totalAt = lines.lastIndexWhere((l) => l.trim() == 'Total');
    if (totalAt >= 0 && totalAt + 3 < lines.length && lines.sublist(totalAt + 1, totalAt + 4).every((l) => _money.hasMatch(l.trim()))) {
      opening = _rwf(lines[totalAt + 3].trim()) - _rwf(lines[totalAt + 1].trim()) + _rwf(lines[totalAt + 2].trim());
    }

    final rows = <StatementRow>[];
    // The first row starts after the column headers, not at the account details above them.
    var blockStart = lines.indexWhere((l) => l.trim() == 'Balance') + 1;
    int? previous = opening;
    for (var i = 0; i + 2 < lines.length; i++) {
      final d = _date.firstMatch(lines[i].trim());
      if (d == null || !_money.hasMatch(lines[i + 1].trim()) || !_money.hasMatch(lines[i + 2].trim())) continue;
      final block = lines
          .sublist(blockStart, i)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !_noise.hasMatch(l))
          .toList();
      blockStart = i + 3;
      if (block.isEmpty) continue;

      final amount = _rwf(lines[i + 1].trim()), balance = _rwf(lines[i + 2].trim());
      final narration = block.first;
      final Direction direction;
      if (previous != null && balance - previous == amount) {
        direction = Direction.inflow;
      } else if (previous != null && previous - balance == amount) {
        direction = Direction.outflow;
      } else {
        // shortcut: rows on the same day are sometimes listed out of order, so
        // the balance chain breaks; fall back to the description. Revisit if
        // real statements show many such rows.
        direction = RegExp(r'^(TPGYBILL|REVERSED)').hasMatch(narration) ? Direction.inflow : Direction.outflow;
      }
      previous = balance;

      final all = block.join(' ');
      final refs = <String>{
        for (final m in RegExp(r'(?:EQ)?(A[0-9A-F]{12})\b').allMatches(all)) m[1]!,
        // Newer references use any letters ("AELSYO5KN8DM"); at least one digit,
        // so a plain word like "AUTHORISATION" is never taken for one.
        for (final m in RegExp(r'\b(A(?=[A-Z]*\d)[0-9A-Z]{11})\b').allMatches(all)) m[1]!,
        // On a line of its own a reference may be letters only ("AELSYOKNABDM").
        for (final l in block)
          if (RegExp(r'^A[0-9A-Z]{11}$').hasMatch(l)) l,
        for (final m in RegExp(r'\b(S\d{6,8})\b').allMatches(all)) m[1]!,
        for (final m in RegExp(r'\b(\d{11})\b').allMatches(all)) m[1]!,
      };
      final (who, phone) = _equityParty(narration);
      rows.add(StatementRow(
        provider: Provider.equity,
        time: DateTime(int.parse(d[3]!), int.parse(d[2]!), int.parse(d[1]!)),
        hasTime: false,
        direction: direction,
        amount: amount,
        balance: balance,
        description: narration,
        refs: refs,
        counterparty: who,
        phone: phone,
        txnRef: block.where((l) => RegExp(r'^\d{6,8}$').hasMatch(l)).firstOrNull,
        details: all,
      ));
    }
    // Newest first (the newer layout): the Balance column still tells money in
    // from money out row by row, but it is not a real balance, so it must not
    // be used to check mine.
    final newestFirst = rows.length > 1 && rows.first.time.isAfter(rows.last.time);
    return foldFees(newestFirst ? [for (final r in rows) r.withoutBalance()] : rows);
  }

  static (String?, String?) _equityParty(String n) {
    RegExpMatch? x;
    if ((x = RegExp(r'^APP/MTN/(\d+)/\w+/(.*?)/?$').firstMatch(n)) != null) {
      final name = x![2]!.trim();
      return (RegExp(r'^\d+$').hasMatch(name) || name.isEmpty ? null : name, x[1]);
    }
    if ((x = RegExp(r'^MC-(.+?)\s*/PURC').firstMatch(n)) != null) return (x![1]!.trim(), null);
    if ((x = RegExp(r'^RNDPS eKash/\w+/(\d+)/(.+?)/?$', caseSensitive: false).firstMatch(n)) != null) {
      return (x![2]!.trim(), x[1]);
    }
    if ((x = RegExp(r'^TPGYBILL eKash/\d+/(\d+)/([^/]+)').firstMatch(n)) != null) return (x![2]!.trim(), x[1]);
    if ((x = RegExp(r'^TPGYBILL (\d+) ').firstMatch(n)) != null) return ('MTN MoMo', x![1]);
    if ((x = RegExp(r'^APP/([^/]+)/$').firstMatch(n)) != null) return (x![1]!.trim(), null);
    return (null, null);
  }
}
