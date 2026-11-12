import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/report.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';

/// Income and spending for a day, week, month, year or custom range, for all
/// accounts or one (spec: Reports and Summaries).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.containing(PeriodKind.month, DateTime.now());

  Future<void> _setKind(PeriodKind k) async {
    if (k == PeriodKind.custom) {
      final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
      if (r == null) return;
      setState(() => _period = Period.custom(r.start, r.end));
      return;
    }
    setState(() => _period = Period.containing(k, _period.kind == PeriodKind.custom ? DateTime.now() : _anchor));
  }

  /// Keeps the same moment in view when switching between Day, Week, Month and Year.
  DateTime get _anchor {
    final now = DateTime.now();
    return _period.contains(now) ? now : _period.start;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ledger = LedgerScope.of(context).ledger;
    final settings = SettingsScope.of(context);
    final account = settings.account;
    final report = Report.build(ledger.txs, _period, account: account, hidden: settings.hidden);
    final t = report.totals;
    final isFuture = !_period.shift(1).start.isBefore(DateTime.now().add(const Duration(days: 1)));

    const kinds = {
      PeriodKind.day: 'Day',
      PeriodKind.week: 'Week',
      PeriodKind.month: 'Month',
      PeriodKind.year: 'Year',
      PeriodKind.custom: 'Custom range…',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(children: [
          Expanded(child: Text('Reports', style: theme.textTheme.headlineMedium)),
          const HideAmountsButton(),
        ]),
        const SizedBox(height: 12),
        // Period and account as drop-downs; the arrows below step through periods.
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<PeriodKind>(
              key: ValueKey(_period.kind),
              initialValue: _period.kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Period', isDense: true, border: OutlineInputBorder()),
              items: [for (final e in kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (k) {
                if (k != null) _setKind(k);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<Provider?>(
              key: ValueKey(account),
              initialValue: account,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account', isDense: true, border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: null, child: Text(settings.hidden.isEmpty ? 'All accounts' : 'All shown')),
                for (final p in settings.visibleAccounts) DropdownMenuItem(value: p, child: Text(p.short)),
              ],
              onChanged: (p) => settings.account = p,
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _period = _period.shift(-1)),
          ),
          Expanded(
            child: InkWell(
              onTap: _period.kind == PeriodKind.custom ? () => _setKind(PeriodKind.custom) : null,
              child: Text(_period.label, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: isFuture ? null : () => setState(() => _period = _period.shift(1)),
          ),
        ]),
        const SizedBox(height: 8),
        _TotalsCard(t, oneAccount: account != null || settings.hidden.isNotEmpty),
        const SizedBox(height: 16),
        _section(context, 'Top spending'),
        _CategoryList(t.topSpending, total: t.spent, empty: 'No confirmed spending in this period.'),
        const SizedBox(height: 16),
        _section(context, 'Top income'),
        _CategoryList(t.topIncome, total: t.income, empty: 'No confirmed income in this period.'),
        const SizedBox(height: 16),
        _section(context, 'Trend'),
        _TrendChart(report.trend),
        const SizedBox(height: 16),
        _section(context, 'By account'),
        Card(
          child: Column(children: [
            if (report.byAccount.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text('Nothing yet.', style: TextStyle(color: muted))),
            for (final a in report.byAccount) ...[_AccountRow(a), const Divider(height: 1)],
          ]),
        ),
      ],
    );
  }

  static Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard(this.t, {required this.oneAccount});
  final Totals t;
  final bool oneAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget line(String label, int v, {bool bold = false, bool signed = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? null : TextStyle(color: muted))),
            Amount(v, signed: signed, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line('Income', t.income),
            line('Spent', t.spent),
            const Divider(),
            line('Difference', t.net, bold: true, signed: true),
            if (oneAccount && (t.movedIn > 0 || t.movedOut > 0)) ...[
              const SizedBox(height: 8),
              line('Moved in from my other accounts', t.movedIn),
              line('Moved out to my other accounts', t.movedOut),
            ],
            if (t.loansIn > 0 || t.loansOut > 0) ...[
              const SizedBox(height: 8),
              line('Loans received (not income)', t.loansIn),
              line('Loan repayments (not spending)', t.loansOut),
            ],
            if (t.pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${t.pendingCount} item${t.pendingCount == 1 ? '' : 's'} still need a category '
                  '(${formatRwf(t.pendingAmount, hidden: SettingsScope.of(context).hideAmounts)}) and are not counted yet.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            if (t.approximate)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Some foreign card charges have no RWF amount yet.', style: TextStyle(color: muted, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList(this.items, {required this.total, required this.empty});
  final List<CategoryTotal> items;
  final int total;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(empty, style: TextStyle(color: scheme.onSurfaceVariant))));
    }
    return Card(
      child: Column(children: [
        for (final c in items)
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CategoryTxs(c))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(c.name)),
                  Text('${total == 0 ? 0 : (100 * c.amount / total).round()}%  ', style: TextStyle(color: scheme.onSurfaceVariant)),
                  Amount(c.amount, style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : c.amount / total,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: scheme.secondary,
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Drill down: the transactions behind one category.
class _CategoryTxs extends StatelessWidget {
  const _CategoryTxs(this.c);
  final CategoryTotal c;

  @override
  Widget build(BuildContext context) {
    final txs = [...c.txs]..sort((a, b) => b.time.compareTo(a.time));
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Amount(c.amount, style: Theme.of(context).textTheme.headlineSmall),
        ),
        for (final t in txs) TxTile(t),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart(this.bars);
  final List<(String, Totals)> bars;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = SettingsScope.of(context).hideAmounts;
    final top = bars.fold<int>(0, (m, b) => math.max(m, math.max(b.$2.spent, b.$2.income)));
    double h(int v) => top == 0 ? 0 : 110 * v / top;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(children: [
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (_, t) in bars)
                  Expanded(
                    child: Tooltip(
                      message: hidden ? '' : 'In ${formatRwf(t.income)}\nOut ${formatRwf(t.spent)}',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(width: 7, height: h(t.income), color: scheme.secondary),
                          const SizedBox(width: 2),
                          Container(width: 7, height: h(t.spent), color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            for (final (label, _) in bars)
              Expanded(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 10, height: 10, color: scheme.secondary),
            const Text('  Income     '),
            Container(width: 10, height: 10, color: scheme.primary),
            const Text('  Spent'),
          ]),
        ]),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow(this.a);
  final AccountSummary a;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget cell(String label, int? v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: muted, fontSize: 12)),
            v == null ? const Text('—') : Amount(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.provider.label,
            style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.secondary)),
        const SizedBox(height: 6),
        Row(children: [
          cell('Income', a.totals.income),
          cell('Spent', a.totals.spent),
          cell(a.provider == Provider.cash ? 'Balance' : 'Closing balance', a.provider == Provider.cash ? null : a.closing),
        ]),
      ]),
    );
  }
}
