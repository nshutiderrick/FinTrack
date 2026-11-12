import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'data/ledger_controller.dart';
import 'data/ledger_store.dart';
import 'firebase_options.dart';
import 'popup/popup_app.dart';
import 'screens/home_screen.dart';
import 'screens/loans_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/review_screen.dart';
import 'screens/transactions_screen.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: AppFirebaseOptions.current);
  final settings = await AppSettings.load();
  final auth = AuthService();
  runApp(ExpenseTrackerApp(
    settings: settings,
    home: AuthGate(auth: auth, signedIn: const Shell()),
    ledger: (child) => UserLedger(auth: auth, child: child),
  ));
}

/// Entry point of the floating category pop-up. The alert listener starts it in
/// a separate engine (android/.../Popup.kt) when a payment needs a category.
@pragma('vm:entry-point')
Future<void> popupMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PopupApp(settings: await AppSettings.load()));
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key, required this.settings, this.home = const Shell(), this.ledger});

  final AppSettings settings;

  /// The login gate in the real app; tests use [Shell] directly.
  final Widget home;

  /// Wraps the navigator with the ledger, so pushed screens see it too.
  /// Tests leave it out and get an in-memory ledger.
  final Widget Function(Widget child)? ledger;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'FinTrack',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          home: home,
          builder: (context, child) =>
              ledger?.call(child!) ?? LedgerHost(store: MemoryLedgerStore(), child: child!),
        ),
      ),
    );
  }
}

/// Bottom-tab shell matching the Figma prototype.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.home_outlined, 'Home'),
    (Icons.error_outline, 'Review'),
    (Icons.bar_chart, 'Reports'),
    (Icons.event_repeat, 'Dues'),
    (Icons.receipt_long, 'Transactions'),
  ];

  @override
  Widget build(BuildContext context) {
    final reviewCount = visibleReviewCount(LedgerScope.of(context).ledger, SettingsScope.of(context));
    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => const HomeScreen(),
          1 => const ReviewScreen(),
          2 => const ReportsScreen(),
          3 => const DuesScreen(),
          _ => const TransactionsScreen(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final (i, (icon, label)) in _tabs.indexed)
            NavigationDestination(
              icon: i == 1 && reviewCount > 0 ? Badge.count(count: reviewCount, child: Icon(icon)) : Icon(icon),
              label: label,
            ),
        ],
      ),
    );
  }
}
