import 'dart:convert';

import 'package:flutter/services.dart';

import 'leaving_app.dart';

/// One notification as the native listener saw it.
class RawAlert {
  const RawAlert({required this.package, required this.title, required this.text, required this.postedAt});

  factory RawAlert.fromJson(Map<String, dynamic> j) => RawAlert(
        package: j['package'] as String,
        title: j['title'] as String,
        text: j['text'] as String,
        postedAt: DateTime.fromMillisecondsSinceEpoch(j['postedAt'] as int),
      );

  final String package;

  /// For SMS this is the sender (M-Money, EQUITYBANK, AirtelMoney).
  final String title;
  final String text;
  final DateTime postedAt;

  Map<String, dynamic> toJson() =>
      {'package': package, 'title': title, 'text': text, 'postedAt': postedAt.millisecondsSinceEpoch};

  /// Stable id for this alert, used as its document id. A hash, so the id
  /// itself reveals nothing about the message.
  String get id => 'a${fnv1a('$package|$title|${postedAt.millisecondsSinceEpoch}|$text')}';

  static const equityApp = 'ke.co.equitygroup.equitymobile';
  static const smsSenders = {'M-Money', 'EQUITYBANK', 'AirtelMoney'};

  /// The sender name [MessageParser] expects, or null if this is not a tracked alert.
  /// Equity app pushes (title "OneEquity") use the same wording as the EQUITYBANK
  /// SMS, so they go through the same rules; the matcher drops the second copy by REF.
  String? get sender {
    if (package == equityApp) return 'EQUITYBANK';
    return smsSenders.contains(title) ? title : null;
  }
}

/// 64-bit FNV-1a as 16 hex digits. Dart ints wrap at 64 bits on Android.
String fnv1a(String s) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Bridge to the Kotlin AlertListenerService (android/.../AlertListenerService.kt).
class AlertsChannel {
  const AlertsChannel();

  static const _methods = MethodChannel('expense_tracker/alerts');
  static const _events = EventChannel('expense_tracker/alerts/stream');

  Future<bool> isListenerEnabled() async => await _safe(() => _methods.invokeMethod<bool>('isListenerEnabled')) ?? false;

  /// The last 50 alerts the listener saw, oldest first (kept in every build).
  Future<List<RawAlert>> recentAlerts() async {
    final raw = await _safe(() => _methods.invokeMethod<String>('recentAlerts')) ?? '[]';
    return (jsonDecode(raw) as List).map((j) => RawAlert.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Every alert the listener has logged since this version was installed,
  /// plus the last 50 from before (the recent buffer), without repeats.
  Future<List<RawAlert>> allAlerts() async {
    final raw = await _safe(() => _methods.invokeMethod<String>('readLog')) ?? '';
    final logged = const LineSplitter()
        .convert(raw)
        .where((l) => l.trim().isNotEmpty)
        .map((l) => RawAlert.fromJson(jsonDecode(l) as Map<String, dynamic>));
    final byId = <String, RawAlert>{};
    for (final a in [...await recentAlerts(), ...logged]) {
      byId[a.id] = a;
    }
    return byId.values.toList();
  }

  /// "Erase all data": forgets the alerts logged on the phone and any pop-up
  /// choices not saved yet. New alerts are still read from now on.
  Future<void> resetLocal() => _safe(() => _methods.invokeMethod<void>('resetLocal'));

  /// When the app was first installed on this phone; null in tests.
  Future<DateTime?> installedAt() async {
    final ms = await _safe(() => _methods.invokeMethod<int>('installedAt'));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// No native side in widget tests: behave like an empty, not-yet-enabled phone.
  static Future<T?> _safe<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens Android's "Notification access" page; the user switches the app on there.
  Future<void> openListenerSettings() {
    expectExternal();
    return _methods.invokeMethod('openListenerSettings');
  }

  Future<bool> isCaptureOn() async => await _methods.invokeMethod<bool>('isCaptureOn') ?? false;

  Future<void> setCapture(bool on) => _methods.invokeMethod('setCapture', on);

  Future<List<RawAlert>> readCaptured() async {
    final raw = await _methods.invokeMethod<String>('readCaptured') ?? '';
    return const LineSplitter()
        .convert(raw)
        .where((l) => l.trim().isNotEmpty)
        .map((l) => RawAlert.fromJson(jsonDecode(l) as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();
  }

  Future<void> clearCaptured() => _methods.invokeMethod('clearCaptured');

  /// Alerts as they arrive while the app is running.
  Stream<RawAlert> get alerts => _events
      .receiveBroadcastStream()
      .map((s) => RawAlert.fromJson(jsonDecode(s as String) as Map<String, dynamic>))
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);
}
