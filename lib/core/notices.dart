import 'loans.dart';
import 'subscriptions.dart';

/// One line on the notifications page.
class Notice {
  const Notice(this.title, this.body, this.when);
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

/// Subscriptions running out within a month, failed or missed renewals,
/// loans due within a week or overdue, and items waiting for review.
List<Notice> buildNotices({
  required SubscriptionBook subs,
  required LoanBook loans,
  required int reviewCount,
  required DateTime now,
}) {
  final out = <Notice>[];
  for (final s in subs.active) {
    final end = s.nextRenewal;
    if (s.failedRecently) out.add(Notice(s.name, 'The last payment failed.', s.failures.last.time));
    if (end == null) continue;
    if (end.isBefore(now)) {
      out.add(Notice(s.name, 'Ran out ${_inDays(end, now)}${s.missed(now) ? ', no payment since' : ''}.', end));
    } else if (end.isBefore(now.add(const Duration(days: 31)))) {
      out.add(Notice(s.name, 'Runs out ${_inDays(end, now)}.', end));
    }
  }
  for (final l in loans.open) {
    final due = l.due;
    if (due == null || due.isAfter(now.add(const Duration(days: 7)))) continue;
    final side = l.side == LoanSide.iOwe ? 'You owe ${l.who}' : '${l.who} owes you';
    out.add(Notice(side, l.overdue(now) ? 'Was due ${_inDays(due, now)}.' : 'Due ${_inDays(due, now)}.', due));
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  if (reviewCount > 0) {
    out.insert(0, Notice('Review', '$reviewCount item${reviewCount == 1 ? '' : 's'} waiting for you.', now));
  }
  return out;
}
