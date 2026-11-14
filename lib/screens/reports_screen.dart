import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/report.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/glass.dart';
import '../widgets/page_header.dart';
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

    return GlassBackdrop(
      child: Column(
        children: [
          const PageHeader('Reports'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // Period and account as drop-downs; the arrows below step through periods.
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<PeriodKind>(
                        key: ValueKey(_period.kind),
                        initialValue: _period.kind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Period',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
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
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
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
                  ],
                ),
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
                // A new period starts with nothing picked.
                _TrendChart(report.trend, key: ValueKey('${_period.label} $account')),
                const SizedBox(height: 16),
                _section(context, 'By account'),
                Card(
                  child: Column(
                    children: [
                      if (report.byAccount.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Nothing yet.', style: TextStyle(color: muted)),
                        ),
                      for (final (i, a) in report.byAccount.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _AccountRow(a),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: bold ? null : TextStyle(color: muted)),
          ),
          Amount(
            v,
            signed: signed,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600),
          ),
        ],
      ),
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
                child: Text(
                  'Some foreign card charges have no RWF amount yet.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(empty, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final c in items)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CategoryTxs(c))),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(c.name)),
                        Text(
                          '${total == 0 ? 0 : (100 * c.amount / total).round()}%  ',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Amount(c.amount, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
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
                  ],
                ),
              ),
            ),
        ],
      ),
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
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Amount(c.amount, style: Theme.of(context).textTheme.headlineSmall),
          ),
          for (final t in txs) TxTile(t),
        ],
      ),
    );
  }
}

/// Income and spending as two lines, one point per day, week or month.
/// Scrolls sideways; touching a point shows its figures in a card above the
/// chart, where the finger does not cover them.
class _TrendChart extends StatefulWidget {
  const _TrendChart(this.points, {super.key});
  final List<(String, Totals)> points;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  static const _pointWidth = 44.0;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final sel = _selected != null && _selected! < points.length ? _selected : null;
    final scheme = Theme.of(context).colorScheme;
    final top = points.fold<int>(0, (m, b) => math.max(m, math.max(b.$2.spent, b.$2.income))) / 100;
    LineChartBarData line(int Function(Totals) v, Color color) => LineChartBarData(
      spots: [for (final (i, (_, t)) in points.indexed) FlSpot(i.toDouble(), v(t) / 100)],
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0)),
    );

    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: top == 0 ? 1 : top * 1.15,
        minX: -0.3,
        maxX: points.length - 0.7,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i != v || i < 0 || i >= points.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(points[i].$1, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        // The picked point stays marked after the finger lifts.
        extraLinesData: ExtraLinesData(
          verticalLines: [
            if (sel != null)
              VerticalLine(x: sel.toDouble(), color: scheme.onSurfaceVariant, strokeWidth: 1, dashArray: [4, 4]),
          ],
        ),
        lineTouchData: LineTouchData(
          touchCallback: (_, response) {
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            final i = spots.first.x.toInt();
            if (i != _selected) setState(() => _selected = i);
          },
          // The figures go in the card above instead of a box on the chart.
          touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) => [for (final _ in spots) null]),
        ),
        lineBarsData: [line((t) => t.income, scheme.secondary), line((t) => t.spent, scheme.primary)],
      ),
    );

    final muted = scheme.onSurfaceVariant;
    Widget figure(String label, int v, {bool signed = false}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
          Amount(
            v,
            signed: signed,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    final details = sel == null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Touch the chart to see the figures for a point.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          )
        : Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(points[sel].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      figure('Income', points[sel].$2.income),
                      figure('Expenses', points[sel].$2.spent),
                      figure('Net', points[sel].$2.net, signed: true),
                    ],
                  ),
                ],
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        details,
        Glass(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true, // start at the latest day
                    child: SizedBox(
                      width: math.max(box.maxWidth, points.length * _pointWidth),
                      height: 180,
                      child: chart,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 14, height: 3, color: scheme.secondary),
                    const Text('  Income     '),
                    Container(width: 14, height: 3, color: scheme.primary),
                    const Text('  Expenses'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
          v == null ? const Text('—') : Amount(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.provider.label,
            style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.secondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              cell('Income', a.totals.income),
              cell('Spent', a.totals.spent),
              cell(
                a.provider == Provider.cash ? 'Balance' : 'Closing balance',
                a.provider == Provider.cash ? null : a.closing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
