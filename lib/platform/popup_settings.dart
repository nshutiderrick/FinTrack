import 'dart:convert';

import 'package:flutter/services.dart';

import '../popup/popup_logic.dart';
import 'leaving_app.dart';

/// One choice made in a pop-up or on its notification, waiting to be saved.
class PopupDecision {
  const PopupDecision({
    required this.alertId,
    required this.title,
    required this.amount,
    required this.time,
    this.category,
    this.description,
    this.lent = false,
    this.transfer = false,
  });

  /// "Between my accounts": my own money moving, not spending or income.
  final bool transfer;

  final String alertId, title;
  final int amount;
  final DateTime time;
  final String? category, description;
  final bool lent;

  static PopupDecision? fromJson(Object? j) {
    if (j is! Map || j['alertId'] is! String) return null;
    return PopupDecision(
      alertId: j['alertId'] as String,
      title: j['title'] as String? ?? '',
      amount: (j['amount'] as num?)?.toInt() ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch((j['time'] as num?)?.toInt() ?? 0),
      category: j['category'] as String?,
      description: j['description'] as String?,
      lent: j['lent'] == true,
      transfer: j['transfer'] == true,
    );
  }
}

/// Bridge to android/.../Popup.kt for the main app.
class PopupSettingsChannel {
  const PopupSettingsChannel();

  static const _c = MethodChannel('expense_tracker/popup_settings');

  static Future<T?> _safe<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      return null; // widget tests
    }
  }

  Future<bool> isOn() async => await _safe(() => _c.invokeMethod<bool>('isOn')) ?? false;
  Future<void> setOn(bool on) => _safe(() => _c.invokeMethod('setOn', on));
  Future<bool> canOverlay() async => await _safe(() => _c.invokeMethod<bool>('canOverlay')) ?? false;
  Future<void> openOverlaySettings() {
    expectExternal();
    return _safe(() => _c.invokeMethod('openOverlaySettings'));
  }

  Future<void> requestNotifications() {
    expectExternal(); // the permission dialog takes the app out of the front
    return _safe(() => _c.invokeMethod('requestNotifications'));
  }
  Future<void> setConfig(PopupConfig config) => _safe(() => _c.invokeMethod('setConfig', jsonEncode(config.toMap())));

  Future<List<PopupDecision>> takeDecisions() async {
    final raw = await _safe(() => _c.invokeMethod<String>('takeDecisions')) ?? '[]';
    return [for (final d in jsonDecode(raw) as List) ?PopupDecision.fromJson(d)];
  }
}
