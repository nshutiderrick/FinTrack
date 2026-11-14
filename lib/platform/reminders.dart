import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/subscriptions.dart';

/// Phone notifications before a subscription runs out (see [Subscription.reminders]).
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('reminders', 'Reminders', channelDescription: 'Subscriptions about to run out'),
  );

  /// Replaces the scheduled reminders with these subscriptions' future ones.
  static Future<void> sync(List<Subscription> subs) async {
    try {
      if (!_ready) {
        tzdata.initializeTimeZones();
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        );
        _ready = true;
      }
      // Only ours: cancelAll would also clear the alert pop-up's notifications.
      for (final p in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(id: p.id);
      }
      final now = DateTime.now();
      var asked = false;
      for (final s in subs) {
        final times = s.reminders;
        for (final (i, at) in times.indexed) {
          if (!at.isAfter(now)) continue;
          if (!asked) {
            asked = true;
            await _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission();
          }
          final end = s.nextRenewal!;
          final dayBefore = i == times.length - 1;
          await _plugin.zonedSchedule(
            id: '${s.record?.id ?? s.key}-$i'.hashCode & 0x7fffffff,
            // An absolute moment, so UTC works without looking up the phone's time zone.
            scheduledDate: tz.TZDateTime.from(at, tz.UTC),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: dayBefore ? '${s.name} runs out tomorrow' : '${s.name} runs out in a month',
            body: 'Paid until ${end.day}/${end.month}/${end.year}.',
          );
        }
      }
    } catch (_) {
      // No plugin in tests; a reminder that could not be set is not worth a crash.
    }
  }
}
