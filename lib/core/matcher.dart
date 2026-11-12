import 'models.dart';

/// A parsed message after duplicate, reversal and transfer matching.
class Matched {
  Matched(this.message)
      : kind = message.kind,
        origin = message;

  ParsedMessage message;

  /// The first copy as it went in, so callers can find their own record for it
  /// after [message] has been merged with later duplicates.
  final ParsedMessage origin;
  Kind kind;

  /// Cancelled by a later reversal. It still moved money, so the balance check
  /// sees it, but reports leave it out.
  bool cancelled = false;

  /// The other half of a transfer between my accounts, or the transaction a
  /// reversal cancelled.
  Matched? pair;

  /// Counts in the income and spending totals (spec: "What counts in the totals").
  bool get inTotals => !cancelled && (kind == Kind.expense || kind == Kind.income);

  /// Moves money, so the balance check must apply it (even if cancelled).
  /// A reversal with nothing to cancel gives back money that was never taken
  /// (the send only got a "Confirmed. Request..." notice), so it moves nothing.
  bool get movesMoney =>
      message.direction != Direction.none &&
      kind != Kind.failed &&
      kind != Kind.ignore &&
      !(kind == Kind.cancel && pair == null);

  @override
  String toString() => 'Matched($kind${cancelled ? ' cancelled' : ''} ${message.provider.name} ${message.amount})';
}

/// Turns the raw stream of parsed alerts into transactions:
/// 1. drops repeated alerts (same provider and reference, at any time gap),
/// 2. cancels the transaction a reversal refers to,
/// 3. pairs a send and a receive between my own accounts as one transfer.
///
/// The result is sorted by transaction time, ready for [BalanceTracker].
class TransactionMatcher {
  /// Two sides of a transfer between my accounts. Equity's older wording only
  /// gives the minute, so this is wider than the 15 s seen in practice.
  static const transferWindow = Duration(seconds: 90);

  /// How far back a reversal without a matching reference may look.
  static const reversalWindow = Duration(days: 3);

  /// Names that turned out to be mine: both sides of a transfer named them.
  final Set<String> learnedNames = {};

  List<Matched> match(Iterable<ParsedMessage> messages) {
    final sorted = messages.toList()..sort((a, b) => a.time.compareTo(b.time));
    final out = <Matched>[];
    final byRef = <String, Matched>{};

    for (final m in sorted) {
      // Direction is part of the key: an Equity reversal reuses the reference
      // of the send it cancels, and must not be merged into it.
      final key = m.reference == null ? null : '${m.provider.name}|${m.direction.name}|${m.reference}';
      final seen = key == null ? null : byRef[key];
      if (seen != null) {
        seen.message = _merge(seen.message, m);
        continue;
      }
      final t = Matched(m);
      if (key != null) byRef[key] = t;
      out.add(t);
    }

    for (final c in out.where((t) => t.kind == Kind.cancel)) {
      final target = _cancelTarget(c, out);
      if (target != null) {
        target
          ..cancelled = true
          ..pair = c;
        c.pair = target;
      }
    }

    _pairTransfers(out);
    return out;
  }

  /// Keeps the first copy but fills in what the duplicate knows better: the
  /// balance ("used to pay your loan" has it, "Your repayment" does not) and a
  /// named person (Airtel's Kohereza names them, the matching Kwishyura does not).
  ParsedMessage _merge(ParsedMessage a, ParsedMessage b) {
    final usePerson = !a.isPerson && b.isPerson;
    return ParsedMessage(
      provider: a.provider,
      kind: a.kind == Kind.needsReview ? b.kind : a.kind,
      time: a.time,
      direction: a.direction,
      amount: a.amount,
      currency: a.currency,
      fee: a.fee > b.fee ? a.fee : b.fee,
      balance: a.balance ?? b.balance,
      counterparty: usePerson ? b.counterparty : (a.counterparty ?? b.counterparty),
      phone: usePerson ? b.phone : (a.phone ?? b.phone),
      isPerson: a.isPerson || b.isPerson,
      reference: a.reference,
      loanId: a.loanId ?? b.loanId,
      categoryHint: a.categoryHint ?? b.categoryHint,
      note: a.note ?? b.note,
    );
  }

  Matched? _cancelTarget(Matched c, List<Matched> all) {
    final m = c.message;
    bool candidate(Matched t) =>
        !identical(t, c) &&
        !t.cancelled &&
        t.message.provider == m.provider &&
        t.message.direction == Direction.outflow &&
        t.message.amount == m.amount &&
        t.message.currency == m.currency &&
        !t.message.time.isAfter(m.time) &&
        m.time.difference(t.message.time) <= reversalWindow;

    // Same reference first ("Transfer request unsuccessful ... Ref. X").
    if (m.reference != null) {
      for (final t in all) {
        if (candidate(t) && t.message.reference == m.reference) return t;
      }
    }
    // Card Auth Reversal: same merchant. Otherwise: the latest same-amount send.
    final options = all.where(candidate).where((t) =>
        m.counterparty == null || t.message.counterparty == null || t.message.counterparty == m.counterparty);
    return options.isEmpty ? null : options.reduce((a, b) => a.message.time.isAfter(b.message.time) ? a : b);
  }

  void _pairTransfers(List<Matched> all) {
    // Sides with no other party, or my own name, can be half of a transfer.
    // A named person can too, but only when the other side names the same
    // person: money I send to "MUGABO JEAN" arriving from "Jean Mugabo"
    // in my other account is me, even before my names are set in Settings.
    bool open(Matched t) => !t.cancelled && t.pair == null;
    bool outSide(Matched t) =>
        open(t) &&
        t.message.direction == Direction.outflow &&
        t.message.rwfKnown &&
        (t.kind == Kind.transfer || t.kind == Kind.needsReview || t.kind == Kind.expense);
    bool inSide(Matched t) =>
        open(t) &&
        t.message.direction == Direction.inflow &&
        (t.kind == Kind.transfer || t.kind == Kind.needsReview || t.kind == Kind.income);
    bool anonymous(Matched t) =>
        t.kind == Kind.transfer || t.kind == Kind.needsReview || (t.kind == Kind.income && !t.message.isPerson);
    bool canPair(Matched o, Matched i) =>
        (anonymous(o) && anonymous(i)) || OwnIdentity.sameName(o.message.counterparty, i.message.counterparty);

    for (final o in all.where(outSide)) {
      Matched? best;
      Duration? bestGap;
      for (final i in all.where(inSide)) {
        if (i.message.provider == o.message.provider || i.message.amount != o.message.amount) continue;
        if (!canPair(o, i)) continue;
        final gap = i.message.time.difference(o.message.time).abs();
        if (gap > transferWindow) continue;
        if (bestGap == null || gap < bestGap) {
          best = i;
          bestGap = gap;
        }
      }
      if (best != null) {
        if (OwnIdentity.sameName(o.message.counterparty, best.message.counterparty)) {
          learnedNames.add(o.message.counterparty!);
        }
        o
          ..kind = Kind.transfer
          ..pair = best;
        best
          ..kind = Kind.transfer
          ..pair = o;
      }
    }
  }
}
