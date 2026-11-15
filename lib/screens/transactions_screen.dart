import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/tx_query.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/page_header.dart';
import '../widgets/tx_widgets.dart';

/// Activity, every transaction: expenses, income and transfers between my accounts.
/// Sort by date, amount or name either way, and filter by category.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TxSort _sort = TxSort.dateDesc;
  final Set<String> _groups = {};
  String _search = '';

  /// Shows only moves between my own accounts, which the main list leaves
  /// out so they do not swell the money in and out.
  bool _between = false;

  Future<void> _pickCategories(List<String> all) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final chosen = {..._groups};
        return StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Filter by category', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(onPressed: () => setSheet(chosen.clear), child: const Text('Clear')),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in all)
                          FilterChip(
                            label: Text(g),
                            selected: chosen.contains(g),
                            onSelected: (on) => setSheet(() => on ? chosen.add(g) : chosen.remove(g)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context, chosen), child: const Text('Show')),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _groups
          ..clear()
          ..addAll(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final settings = SettingsScope.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final account = settings.account;
    bool inView(Provider p) => account == null ? settings.isVisible(p) : p == account;

    final base = c.ledger.txs.where((t) => inView(t.provider) && (t.kind == Kind.transfer) == _between);
    final all = groupsIn(base, [
      ...c.expenseCategories,
      ...c.incomeCategories.where((x) => !c.expenseCategories.contains(x)),
    ]);
    _groups.retainWhere(all.contains);
    final list = queryTxs(base, sort: _sort, groups: _groups, search: _search);
    var moneyIn = 0, moneyOut = 0;
    for (final t in list) {
      if (t.cancelled) continue;
      if (t.m.direction == Direction.inflow) {
        moneyIn += t.rwf;
      } else {
        moneyOut += t.rwf;
      }
    }

    final scheme = theme.colorScheme;
    Widget flow(IconData icon, String label, int amount, Color color) => Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 12)),
              Amount(amount, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
        ),
      ],
    );
    final summary = Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _between
                  ? '${list.length} move${list.length == 1 ? '' : 's'} between my accounts'
                  : '${list.length} transaction${list.length == 1 ? '' : 's'}',
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: flow(Icons.south_west, 'Money in', moneyIn, scheme.secondary)),
                  VerticalDivider(width: 24, color: scheme.outlineVariant),
                  Expanded(child: flow(Icons.north_east, 'Money out', moneyOut, scheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const PageHeader('Activity'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search names and descriptions',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Provider?>(
                      key: ValueKey(account),
                      initialValue: account,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(settings.hidden.isEmpty ? 'All accounts' : 'All shown'),
                        ),
                        for (final p in settings.visibleAccounts) DropdownMenuItem(value: p, child: Text(p.short)),
                      ],
                      onChanged: (p) => settings.account = p,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Between my accounts'),
                    selected: _between,
                    showCheckmark: false,
                    onSelected: (v) => setState(() => _between = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TxSort>(
                      initialValue: _sort,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sort', isDense: true, border: OutlineInputBorder()),
                      items: [for (final s in TxSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
                      onChanged: (s) => setState(() => _sort = s ?? _sort),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => _pickCategories(all),
                    icon: const Icon(Icons.filter_list),
                    label: Text(_groups.isEmpty ? 'Categories' : '${_groups.length} chosen'),
                  ),
                ],
              ),
            ),
            if (_groups.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final g in _groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 8),
                        child: InputChip(label: Text(g), onDeleted: () => setState(() => _groups.remove(g))),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        _between ? 'No moves between your accounts.' : 'Nothing matches.',
                        style: TextStyle(color: muted),
                      ),
                    )
                  // The count and totals are the first item, so they scroll away with the list.
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: list.length + 1,
                      itemBuilder: (_, i) => i > 0 ? TxTile(list[i - 1]) : summary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
