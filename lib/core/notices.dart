import 'ledger.dart';
import 'loans.dart';
import 'subscriptions.dart';

/// One line on the notifications page.
class Notice {
  const Notice(this.id, this.title, this.body, this.when);

  /// Stays the same while the notice is about the same thing, and changes
  /// when something new happens, so a read notice comes back only for news.
  final String id;
  final String title, body;

  /// The date it is about, for sorting (soonest first).
  final DateTime when;
}

String _inDays(DateTime d, DateTime now) {
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days < 0) return '${-days} day${days == -1 ? '' : 's'} ago';
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  return 'in $days days';
}

Tx _newest(Iterable<Tx> txs) => txs.reduce((a, b) => b.time.isAfter(a.time) ? b : a);

/// Pending transactions and unapproved mismatches first, then subscriptions
/// whose reminder day has come (a month and a day before they run out) or
/// that ran out or failed, then loans due within a week or overdue.
List<Notice> buildNotices({
  required SubscriptionBook subs,
  required LoanBook loans,
  required List<Tx> pending,
  required List<Mismatch> mismatches,
  required DateTime now,
}) {
  final out = <Notice>[];
  for (final s in subs.active) {
    final k = s.record?.id ?? s.key;
    if (s.failedRecently) {
      final f = s.failures.last.time;
      out.add(Notice('subfail:$k:${f.millisecondsSinceEpoch}', s.name, 'The last payment failed.', f));
    }
    final end = s.nextRenewal;
    if (end == null) continue;
    if (end.isBefore(now)) {
      out.add(
        Notice(
          'subend:$k:${end.millisecondsSinceEpoch}',
          s.name,
          'Ran out ${_inDays(end, now)}${s.missed(now) ? ', no payment since' : ''}.',
          end,
        ),
      );
      continue;
    }
    final reached = s.reminders.where((r) => !r.isAfter(now));
    if (reached.isNotEmpty) {
      out.add(Notice('sub:$k:${reached.last.millisecondsSinceEpoch}', s.name, 'Runs out ${_inDays(end, now)}.', end));
    }
  }
  for (final l in loans.open) {
    final due = l.due;
    if (due == null || due.isAfter(now.add(const Duration(days: 7)))) continue;
    final late = l.overdue(now);
    out.add(
      Notice(
        'loan:${l.id}:${due.millisecondsSinceEpoch}:${late ? 'late' : 'soon'}',
        l.side == LoanSide.iOwe ? 'You owe ${l.who}' : '${l.who} owes you',
        late ? 'Was due ${_inDays(due, now)}.' : 'Due ${_inDays(due, now)}.',
        due,
      ),
    );
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return [
    if (pending.isNotEmpty)
      Notice(
        'pending:${_newest(pending).id}',
        'Pending transactions',
        '${pending.length} waiting for a category or a type.',
        now,
      ),
    if (mismatches.isNotEmpty)
      Notice(
        'mismatch:${_newest([for (final m in mismatches) m.tx]).id}',
        'Mismatches',
        '${mismatches.length} balance gap${mismatches.length == 1 ? '' : 's'} not approved yet.',
        now,
      ),
    ...out,
  ];
}
