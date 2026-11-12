import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models.dart';

/// User preferences that change how the whole app looks. Saved on the phone.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs)
      : _themeMode = ThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? ThemeMode.system,
        _hideAmounts = _prefs.getBool(_hideKey) ?? false,
        _account = Provider.values.asNameMap()[_prefs.getString(_accountKey)];

  static const _themeKey = 'themeMode', _hideKey = 'hideAmounts', _accountKey = 'accountFilter';

  Provider? _account;

  /// The account filter on Home and Reports; null is all accounts. Remembered.
  /// A hidden account is never the filter.
  Provider? get account => _account != null && hidden.contains(_account) ? null : _account;
  set account(Provider? p) {
    _account = p;
    p == null ? _prefs.remove(_accountKey) : _prefs.setString(_accountKey, p.name);
    notifyListeners();
  }

  static const _hiddenKey = 'hiddenAccounts';

  /// Accounts I turned off. They keep recording in the background (alerts,
  /// balances, matching), but every total, list and chart leaves them out
  /// until I turn them back on.
  Set<Provider> get hidden => {
        for (final n in _prefs.getStringList(_hiddenKey) ?? const <String>[]) ?Provider.values.asNameMap()[n],
      };

  bool isVisible(Provider p) => !hidden.contains(p);
  List<Provider> get visibleAccounts => Provider.values.where(isVisible).toList();

  void setVisible(Provider p, bool visible) {
    final h = hidden;
    visible ? h.remove(p) : h.add(p);
    _prefs.setStringList(_hiddenKey, [for (final x in h) x.name]);
    notifyListeners();
  }

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  bool _hideAmounts;

  /// System (follows the phone), light or dark.
  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode m) {
    _themeMode = m;
    _prefs.setString(_themeKey, m.name);
    notifyListeners();
  }

  /// Hides every balance and amount, e.g. when someone is looking at the screen.
  bool get hideAmounts => _hideAmounts;
  set hideAmounts(bool v) {
    _hideAmounts = v;
    _prefs.setBool(_hideKey, v);
    notifyListeners();
  }
}

/// Makes [AppSettings] available to every widget and rebuilds them when it changes.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child}) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
