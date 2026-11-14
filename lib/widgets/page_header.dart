import 'package:flutter/material.dart';

import '../core/notices.dart';
import '../data/ledger_controller.dart';
import '../screens/notifications_screen.dart';
import '../screens/review_screen.dart';
import '../screens/settings_screen.dart';
import '../settings.dart';
import 'amount.dart';

/// What the notifications page lists, for the badge and the page itself.
List<Notice> noticesOf(BuildContext context) {
  final c = LedgerScope.of(context);
  return buildNotices(
    subs: c.subscriptions,
    loans: c.loans,
    reviewCount: visibleReviewCount(c.ledger, SettingsScope.of(context)),
    now: DateTime.now(),
  );
}

/// A page title with the hide-amounts, notifications and settings buttons.
/// Pages put it above their scrolling part, so it stays in place.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 16, 12, 4, 4),
      child: Row(
        children: [
          if (canPop) const BackButton(),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.headlineMedium, overflow: TextOverflow.ellipsis),
          ),
          const HideAmountsButton(),
          const NotificationsButton(),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}

class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final n = noticesOf(context).length;
    return IconButton(
      tooltip: n == 0 ? 'Notifications' : '$n notifications',
      icon: Badge.count(count: n, isLabelVisible: n > 0, child: const Icon(Icons.notifications_outlined)),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
    );
  }
}
