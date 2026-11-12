import 'package:flutter/material.dart';

import '../core/ledger.dart';
import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';
import 'manual_entry_screen.dart';

/// Items to review on accounts that are shown. Hidden accounts' items wait and
/// come back when the account is turned on again.
(List<Mismatch>, List<Tx>, List<Tx>) visibleReview(Ledger l, AppSettings s) => (
      l.openMismatches.where((x) => s.isVisible(x.provider)).toList(),
      l.pending.where((t) => s.isVisible(t.provider)).toList(),
      l.unknown.where((t) => s.isVisible(t.provider)).toList(),
    );

int visibleReviewCount(Ledger l, AppSettings s) {
  final (a, b, c) = visibleReview(l, s);
  return a.length + b.length + c.length;
}

/// Review, in two tabs: "Needs review" (items waiting for a category, and
/// messages the app could not classify) and "Mismatches" (balance gaps).
/// The app never guesses; this is where I answer.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final theme = Theme.of(context);
    final (mismatches, pending, unknown) = visibleReview(c.ledger, SettingsScope.of(context));
    final needs = pending.length + unknown.length;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(child: Text('Review', style: theme.textTheme.headlineMedium)),
            const HideAmountsButton(),
          ]),
        ),
        TabBar(tabs: [
          Tab(text: needs == 0 ? 'Needs review' : 'Needs review ($needs)'),
          Tab(text: mismatches.isEmpty ? 'Mismatches' : 'Mismatches (${mismatches.length})'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _NeedsReviewTab(pending: pending, unknown: unknown),
            _MismatchesTab(mismatches),
          ]),
        ),
      ]),
    );
  }
}

class _MismatchesTab extends StatelessWidget {
  const _MismatchesTab(this.mismatches);
  final List<Mismatch> mismatches;

  Future<void> _acceptAll(BuildContext context) async {
    final c = LedgerScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Accept all ${mismatches.length} as is?'),
        content: const Text('Each gap is kept as unexplained and leaves this list. '
            'Balances do not change, and you can still add missing entries by hand later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accept all')),
        ],
      ),
    );
    if (ok == true) c.acceptMismatches([for (final x in mismatches) x.tx.id]);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (!c.loaded)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (mismatches.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('No balance gaps. When a message shows a balance that does not add up, it appears here.',
                textAlign: TextAlign.center, style: TextStyle(color: muted)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('Explain a gap by adding what you spent or received, or accept it.',
                    style: TextStyle(color: muted, fontSize: 13)),
              ),
              TextButton(onPressed: () => _acceptAll(context), child: const Text('Accept all as is')),
            ]),
          ),
        for (final x in mismatches) _MismatchCard(x),
      ]),
    );
  }
}

class _NeedsReviewTab extends StatelessWidget {
  const _NeedsReviewTab({required this.pending, required this.unknown});
  final List<Tx> pending, unknown;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final theme = Theme.of(context);
    Widget header(String title, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text('$title ($n)', style: theme.textTheme.titleMedium),
        );

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final name in c.suggestedNames)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Is "$name" you?', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Money left one of your accounts and arrived in another under this name. '
                      'Saving it lets the app spot transfers where only one side sends an alert.'),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => c.addOwnName(name), child: const Text('Yes, that is me')),
                  ]),
                ]),
              ),
            ),
          if (!c.loaded)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (pending.isEmpty && unknown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('All caught up. New alerts that need an answer will show here.',
                  textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (pending.isNotEmpty) ...[
            header('Pick a category', pending.length),
            for (final t in pending) TxTile(t, onTap: () => showCategorySheet(context, t)),
          ],
          if (unknown.isNotEmpty) ...[
            header('What is this?', unknown.length),
            for (final t in unknown) _UnknownTile(t),
          ],
        ],
      ),
    );
  }
}

class _MismatchCard extends StatelessWidget {
  const _MismatchCard(this.x);
  final Mismatch x;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final o = x.outcome;
    Widget row(String label, int v) => Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: muted))),
          Amount(v),
        ]);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${x.provider.label} · ${dateLabel(x.tx.time)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(children: [
                row('Expected', o.expected),
                row('Message shows', o.actual),
                row(o.gap < 0 ? 'Missing (spent without an alert?)' : 'Extra (received without an alert?)', o.gap),
              ]),
            ),
            if (o.approximate)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Includes a foreign card charge, so the expected figure is approximate.',
                    style: TextStyle(color: muted, fontSize: 12)),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => LedgerScope.of(context).acceptMismatch(x.tx.id),
                  child: const Text('Accept as is'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ManualEntryScreen(
                      account: x.provider,
                      time: x.tx.time.subtract(const Duration(minutes: 1)),
                      gap: o.gap,
                    ),
                  )),
                  child: Text(o.gap < 0 ? 'Add what I spent' : 'Add what I received'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnknownTile extends StatelessWidget {
  const _UnknownTile(this.t);
  final Tx t;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final dir = t.m.direction;
    Widget choice(String label, Kind k) =>
        Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(label), onPressed: () => c.setKind(t.id, k)));
    // One card: the transaction and the answers to "What is this?".
    return ItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TxTile(t, card: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(runSpacing: 8, children: [
              if (dir == Direction.outflow) choice('Spending', Kind.expense),
              if (dir == Direction.inflow) choice('Income', Kind.income),
              if (dir != Direction.none) choice('Between my accounts', Kind.transfer),
              choice('Ignore', Kind.ignore),
            ]),
          ),
        ],
      ),
    );
  }
}
