import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/tx_query.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';

/// Every transaction: expenses, income and transfers between my accounts.
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
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Filter by category', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: () => setSheet(chosen.clear), child: const Text('Clear')),
              ]),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in all)
                      FilterChip(
                        label: Text(g),
                        selected: chosen.contains(g),
                        onSelected: (on) => setSheet(() => on ? chosen.add(g) : chosen.remove(g)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context, chosen), child: const Text('Show')),
            ]),
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

    final base = c.ledger.txs.where((t) => inView(t.provider));
    final all = groupsIn(base, [...c.expenseCategories, ...c.incomeCategories.where((x) => !c.expenseCategories.contains(x))]);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions'), actions: const [HideAmountsButton()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search names and descriptions', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: AccountFilterBar()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
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
          ]),
        ),
        if (_groups.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final g in _groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: InputChip(label: Text(g), onDeleted: () => setState(() => _groups.remove(g))),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Text('${list.length} transactions', style: TextStyle(color: muted)),
            const Spacer(),
            Text('in ', style: TextStyle(color: muted)),
            Amount(moneyIn, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('  out ', style: TextStyle(color: muted)),
            Amount(moneyOut, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Nothing matches.', style: TextStyle(color: muted)))
              : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => TxTile(list[i])),
        ),
      ]),
    );
  }
}
