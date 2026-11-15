import 'package:flutter/material.dart';

import '../core/notices.dart';
import '../settings.dart';
import '../widgets/page_header.dart';
import '../widgets/tx_widgets.dart';

/// Pending transactions, mismatches, subscriptions running out and loans due.
/// Each one is marked as read with its button; read ones move down and stop
/// counting on the bell.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final notices = noticesOf(context);
    final read = settings.readNotices;
    final unread = notices.where((n) => !read.contains(n.id)).toList();
    final done = notices.where((n) => read.contains(n.id)).toList();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget tile(Notice n, {required bool isRead}) => ItemCard(
      child: ListTile(
        leading: Icon(
          isRead ? Icons.notifications_none : Icons.notifications_active_outlined,
          color: isRead ? muted : null,
        ),
        title: Text(
          n.title,
          style: isRead ? TextStyle(color: muted) : const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(n.body),
        trailing: isRead
            ? null
            : TextButton(
                onPressed: () => settings.markNoticeRead(n.id, [for (final x in notices) x.id]),
                child: const Text('Mark as read'),
              ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notices.isEmpty
          ? Center(
              child: Text('Nothing needs you right now.', style: TextStyle(color: muted)),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                if (unread.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text('All read.', style: TextStyle(color: muted)),
                  ),
                for (final n in unread) tile(n, isRead: false),
                if (done.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
                    child: Text(
                      'READ',
                      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final n in done) tile(n, isRead: true),
                ],
              ],
            ),
    );
  }
}
