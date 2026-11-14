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
    // The heading sits above its card, outside it.
    List<Widget> section(String label, List<Widget> children) => [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ...section('Appearance', [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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
              subtitle: const Text('Show amounts as RWF •••••'),
              value: settings.hideAmounts,
              onChanged: (v) => settings.hideAmounts = v,
            ),
            ListTile(
              title: const Text('Accounts shown'),
              subtitle: Text('${settings.visibleAccounts.length} of ${Provider.values.length} shown'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsShownScreen())),
            ),
          ]),
          ...section('Me', [
            ListTile(
              title: const Text('My names and accounts'),
              subtitle: Text(
                '${LedgerScope.of(context).ownNames.length} names, ${LedgerScope.of(context).ownAccounts.length} accounts',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdentityScreen())),
            ),
            ListTile(
              title: const Text('People'),
              subtitle: const Text('Who you pay and get paid by'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PeopleScreen())),
            ),
            ListTile(
              title: const Text('Categories'),
              subtitle: const Text('Add or rename'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
          ]),
          ...section('Data', [
            ListTile(
              title: const Text('Import a statement'),
              subtitle: const Text('MoMo or Equity PDF'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatementImportScreen())),
            ),
            ListTile(
              title: const Text('Erase all data'),
              subtitle: const Text('Start again from today'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EraseScreen())),
            ),
          ]),
          ...section('Alerts', [
            const PopupSettingsTile(),
            ListTile(
              title: const Text('Alert capture'),
              subtitle: const Text('Notification access, saved alerts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaptureScreen())),
            ),
          ]),
          ...section('Security', [
            ListTile(
              title: const Text('Change passcode'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasscodeScreen())),
            ),
          ]),
          ...section('Account', [
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
          ]),
        ],
      ),
    );
  }
}

/// Which accounts Home, lists and reports include. Hidden ones keep recording.
class AccountsShownScreen extends StatelessWidget {
  const AccountsShownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts shown')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'A hidden account keeps recording in the background. Turn it back on and nothing is missing.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final p in Provider.values)
                  SwitchListTile(
                    title: Text(p.label),
                    value: settings.isVisible(p),
                    // At least one account stays visible.
                    onChanged: settings.isVisible(p) && settings.visibleAccounts.length == 1
                        ? null
                        : (v) => settings.setVisible(p, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
