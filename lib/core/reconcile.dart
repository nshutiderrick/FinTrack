import 'matcher.dart';
import 'models.dart';
import 'statement.dart';

/// What importing a statement found (spec: "Statement Import").
class ReconcileResult {
  ReconcileResult();

  /// Statement rows that match a transaction the app already has.
  final List<(StatementRow, Matched)> known = [];

  /// Rows no alert ever reported, as transactions to add ("From statement").
  final List<ParsedMessage> missing = [];

  /// MoMo payments to "EQUITY BANK RWANDA" confirmed as transfers to my Equity
  /// account, because an Equity TPGYBILL row carries their MoMo id.
  final List<Matched> confirmedTransfers = [];

  /// Foreign card charges and the RWF amount the Equity statement shows for them.
  final List<(Matched, int)> foreignAmounts = [];

  /// Transactions whose statement fee (charges folded in) is higher than the
  /// alert showed, and that fee. The fee is replaced, never added to.
  final List<(Matched, int)> feeFixes = [];
}

class StatementReconciler {
  StatementReconciler(this.me);

  final OwnIdentity me;

  static const momoWindow = Duration(minutes: 2);

  ReconcileResult reconcile(List<StatementRow> rows, List<Matched> existing) {
    final result = ReconcileResult();
    final used = <Matched>{};
    final byRef = <String, Matched>{};
    for (final t in existing) {
      final ref = t.message.reference;
      if (ref != null) byRef['${t.message.provider.name}|$ref'] = t;
    }

    for (final row in rows) {
      // MoMo money that arrived on Equity names the MoMo id: confirm that payment as a transfer.
      if (row.provider == Provider.equity && row.direction == Direction.inflow) {
        for (final ref in row.refs) {
          final momo = byRef['mtn|$ref'];
          if (momo != null && momo.message.direction == Direction.outflow && momo.kind != Kind.transfer) {
            momo.kind = Kind.transfer;
            result.confirmedTransfers.add(momo);
          }
        }
      }

      final hit = _byReference(row, byRef, used) ?? _byAmountAndTime(row, existing, used);
      if (hit != null) {
        used.add(hit);
        result.known.add((row, hit));
        if (!hit.message.rwfKnown && row.provider == Provider.equity) result.foreignAmounts.add((hit, row.amount));
        if (row.fee > hit.message.fee) result.feeFixes.add((hit, row.fee));
      } else {
        result.missing.add(_toMessage(row));
      }
    }
    return result;
  }

  Matched? _byReference(StatementRow row, Map<String, Matched> byRef, Set<Matched> used) {
    for (final ref in row.refs) {
      final t = byRef['${row.provider.name}|$ref'];
      if (t != null && !used.contains(t) && t.message.direction == row.direction) return t;
    }
    return null;
  }

  Matched? _byAmountAndTime(StatementRow row, List<Matched> existing, Set<Matched> used) {
    Matched? best;
    Duration? bestGap;
    for (final t in existing) {
      final m = t.message;
      if (used.contains(t) || m.provider != row.provider || m.direction != row.direction) continue;
      final Duration gap;
      if (row.hasTime) {
        if (m.amount != row.amount) continue;
        gap = m.time.difference(row.time).abs();
        if (gap > momoWindow) continue;
      } else {
        // Equity: value date only. A foreign card charge is matched on merchant, since its amount differs.
        final sameMerchant = !m.rwfKnown &&
            m.counterparty != null &&
            row.counterparty != null &&
            row.counterparty!.toUpperCase().startsWith(m.counterparty!.toUpperCase().split(RegExp(r'[\s*]')).first);
        if (m.amount != row.amount && !sameMerchant) continue;
        final day = DateTime(m.time.year, m.time.month, m.time.day);
        gap = day.difference(row.time).abs();
        if (gap > const Duration(days: 1)) continue;
      }
      if (bestGap == null || gap < bestGap) {
        best = t;
        bestGap = gap;
      }
    }
    return best;
  }

  /// A statement row as a transaction, classified with the same "is it me?" rules as alerts.
  ParsedMessage _toMessage(StatementRow row) {
    final own = me.isOwn(name: row.counterparty, phone: row.phone) ||
        RegExp(r'^(APP/MTN/|TPGYBILL )').hasMatch(row.description) ||
        (row.counterparty?.toUpperCase().contains('EKASH') ?? false);
    final Kind kind;
    if (row.description.startsWith('REVERSED')) {
      kind = Kind.cancel;
    } else if (own) {
      kind = Kind.transfer;
    } else {
      kind = row.direction == Direction.inflow ? Kind.income : Kind.expense;
    }
    return ParsedMessage(
      provider: row.provider,
      kind: kind,
      time: row.time,
      direction: row.direction,
      amount: row.amount,
      fee: row.fee,
      balance: row.balanceKnown ? row.balance : null,
      counterparty: row.counterparty,
      phone: row.phone,
      isPerson: kind != Kind.transfer && row.phone != null,
      reference: row.refs.isEmpty ? null : row.refs.first,
      note: 'statement',
    );
  }
}
