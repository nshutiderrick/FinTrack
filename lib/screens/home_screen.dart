import 'package:flutter/material.dart';

import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/glass.dart';
import '../widgets/tx_widgets.dart';
import 'manual_entry_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

/// Overview: balance per account and the latest transactions.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final l = c.ledger;
    final settings = SettingsScope.of(context);
    final account = settings.account;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Hidden accounts keep their balance up to date in the ledger; they are only left out here.
    final balances = {
      for (final e in l.balances.entries)
        if (account == null ? settings.isVisible(e.key) : e.key == account) e.key: e.value,
    };
    final total = balances.values.fold<int>(0, (sum, b) => sum + b.balance);
    final recent = l.txs
        .where((t) => account == null ? settings.isVisible(t.provider) : t.provider == account)
        .take(40)
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ManualEntryScreen(account: account))),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: GlassBackdrop(
        child: RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Overview', style: theme.textTheme.headlineMedium)),
                  const HideAmountsButton(),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const AccountFilterBar(),
              const SizedBox(height: 8),
              if (!c.listenerEnabled)
                Card(
                  child: ListTile(
                    title: const Text('Turn on notification access'),
                    subtitle: const Text('Needed to read your MTN, Airtel and Equity alerts.'),
                    trailing: TextButton(onPressed: c.alerts.openListenerSettings, child: const Text('Turn on')),
                  ),
                ),
              Glass(
                tint: scheme.primary,
                opacity: 0.75,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account != null
                            ? '${account.label} balance'
                            : settings.hidden.isEmpty
                            ? 'Total balance'
                            : 'Total balance (${settings.hidden.length} account${settings.hidden.length == 1 ? '' : 's'} hidden)',
                        style: TextStyle(color: scheme.onPrimary),
                      ),
                      const SizedBox(height: 4),
                      balances.isEmpty
                          ? Text(
                              'Waiting for alerts',
                              style: theme.textTheme.titleLarge?.copyWith(color: scheme.onPrimary),
                            )
                          : Amount(
                              total,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
              if (account == null) ...[
                const SizedBox(height: 8),
                Glass(
                  tint: scheme.secondary,
                  opacity: 0.8,
                  child: ListTileTheme(
                    textColor: scheme.onSecondary,
                    child: Column(
                      children: [
                        for (final p in settings.visibleAccounts)
                          if (p != Provider.cash || l.balances[p] != null)
                            ListTile(
                              title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                l.balances[p] == null
                                    ? 'No balance yet. It appears with the next alert that shows one.'
                                    : 'Last checked ${dateLabel(l.balances[p]!.asOf)}',
                                style: TextStyle(color: scheme.onSecondary.withValues(alpha: 0.8)),
                              ),
                              trailing: l.balances[p] == null
                                  ? null
                                  : Amount(
                                      l.balances[p]!.balance,
                                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSecondary),
                                    ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Latest', style: theme.textTheme.titleMedium)),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                    child: const Text('See all'),
                  ),
                ],
              ),
              if (!c.loaded)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No transactions yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final t in recent.take(15)) TxTile(t, margin: ItemCard.inPadded),
              if (recent.length > 15)
                Center(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                    child: const Text('All transactions'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
