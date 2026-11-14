import 'package:flutter/material.dart';

import '../widgets/page_header.dart';
import '../widgets/tx_widgets.dart';

/// Subscriptions running out, loans due and items to review.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notices = noticesOf(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notices.isEmpty
          ? Center(child: Text('Nothing needs you right now.', style: TextStyle(color: muted)))
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                for (final n in notices)
                  ItemCard(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(n.title),
                      subtitle: Text(n.body),
                    ),
                  ),
              ],
            ),
    );
  }
}
