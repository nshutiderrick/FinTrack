import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../security/app_lock.dart';
import '../settings.dart';
import '../widgets/popup_settings_tile.dart';
import 'capture_screen.dart';
import 'categories_screen.dart';
import 'erase_screen.dart';
import 'identity_screen.dart';
import 'people_screen.dart';
import 'statement_import_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget section(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(label.toUpperCase(), style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          section('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.themeMode = s.single,
            ),
          ),
          SwitchListTile(
            title: const Text('Hide amounts'),
            subtitle: const Text('Show balances and amounts as RWF •••••. The eye on Home does the same.'),
            value: settings.hideAmounts,
            onChanged: (v) => settings.hideAmounts = v,
          ),
          section('Accounts shown'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'A hidden account keeps recording in the background. Totals, lists and reports leave it out '
              'until you turn it back on, and nothing is missed in between.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          for (final p in Provider.values)
            SwitchListTile(
              title: Text(p.label),
              value: settings.isVisible(p),
              // At least one account stays visible.
              onChanged: settings.isVisible(p) && settings.visibleAccounts.length == 1 ? null : (v) => settings.setVisible(p, v),
            ),
          section('Me'),
          ListTile(
            title: const Text('My names and accounts'),
            subtitle: Text('${LedgerScope.of(context).ownNames.length} names, ${LedgerScope.of(context).ownAccounts.length} accounts. '
                'Used to spot transfers between them.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdentityScreen())),
          ),
          ListTile(
            title: const Text('People'),
            subtitle: const Text('Who I send money to and receive it from'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PeopleScreen())),
          ),
          ListTile(
            title: const Text('Categories'),
            subtitle: const Text('Add or rename categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          section('Data'),
          ListTile(
            title: const Text('Import a statement'),
            subtitle: const Text('MoMo or Equity PDF, to find what the alerts missed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatementImportScreen())),
          ),
          ListTile(
            title: const Text('Erase all data'),
            subtitle: const Text('Delete everything and start again from today'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EraseScreen())),
          ),
          section('Alerts'),
          const PopupSettingsTile(),
          ListTile(
            title: const Text('Alert capture'),
            subtitle: const Text('Notification access and saved raw alerts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaptureScreen())),
          ),
          section('Security'),
          ListTile(
            title: const Text('Change passcode'),
            subtitle: const Text('Asked whenever you open FinTrack or come back to it'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasscodeScreen())),
          ),
          section('Account'),
          ListTile(
            title: const Text('Signed in'),
            subtitle: Text(FirebaseAuth.instance.currentUser?.email ?? '—'),
            trailing: TextButton(
              onPressed: () async {
                await AuthService().signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}
