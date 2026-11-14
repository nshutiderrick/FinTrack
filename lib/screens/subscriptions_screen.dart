import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/subscriptions.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';
import '../widgets/glass.dart';
import 'tx_detail_screen.dart';

/// What I pay for regularly, and when it renews (spec: Subscriptions).
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final book = c.subscriptions;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget header(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: theme.textTheme.titleMedium));

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: kBottomBarClearance),
        child: FloatingActionButton.extended(
          heroTag: 'addSubscription',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddSubscriptionScreen())),
          icon: const Icon(Icons.add),
          label: const Text('Add subscription'),
        ),
      ),
      // The second tab of Dues, which has the page title.
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Per month', style: TextStyle(color: muted, fontSize: 12)),
                      Amount(book.monthlyRwf, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                    ]),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Per year', style: TextStyle(color: muted, fontSize: 12)),
                      Amount(book.yearlyRwf, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                    ]),
                  ),
                ]),
                if (book.costApproximate)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Some foreign charges have no RWF amount yet, so they are left out.', style: TextStyle(color: muted, fontSize: 12)),
                  ),
              ]),
            ),
          ),
        ),
        if (book.suggestions.isNotEmpty) ...[
          header('Looks like a subscription'),
          for (final s in book.suggestions) _SuggestionTile(s),
        ],
        header('Active'),
        if (book.active.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('None yet. Repeating card charges are suggested above, or add one by hand.', style: TextStyle(color: muted)),
          ),
        for (final s in book.active) _SubTile(s),
        if (book.cancelled.isNotEmpty) ...[
          header('Cancelled'),
          for (final s in book.cancelled) _SubTile(s),
        ],
      ]),
    );
  }
}

String _price(Subscription s, bool hidden) {
  if (s.rwf != null) return formatRwf(s.rwf!, hidden: hidden);
  final a = s.amount;
  if (a == null) return '—';
  return hidden ? '${s.currency} •••••' : '${s.currency} ${(a / 100).toStringAsFixed(2)}';
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile(this.s);
  final Subscription s;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final hidden = SettingsScope.of(context).hideAmounts;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${s.cycle.label} · ${_price(s, hidden)} · ${s.payments.length} payments, last ${dateLabel(s.lastPaid!, withTime: false)}'),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => c.dismissSubscription(s), child: const Text('Not a subscription')),
            TextButton(onPressed: () => c.trackSubscription(s), child: const Text('Track it')),
          ]),
        ]),
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile(this.s);
  final Subscription s;

  @override
  Widget build(BuildContext context) {
    final hidden = SettingsScope.of(context).hideAmounts;
    final now = DateTime.now();
    final next = s.nextRenewal;
    final flags = [
      s.cycle.label,
      if (s.status == SubStatus.active && next != null) 'renews ${dateLabel(next, withTime: false)}',
      if (s.failedRecently) 'PAYMENT FAILED',
      if (s.missed(now)) 'no payment since renewal',
    ];
    return ItemCard(
      child: ListTile(
        title: Text(s.name),
        subtitle: Text(flags.join(' · ')),
        trailing: Text(_price(s, hidden), style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubscriptionDetailScreen(s.record!.id))),
      ),
    );
  }
}

class SubscriptionDetailScreen extends StatelessWidget {
  const SubscriptionDetailScreen(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final book = c.subscriptions;
    final s = [...book.active, ...book.cancelled].where((x) => x.record?.id == id).firstOrNull;
    if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This subscription is no longer here.')));
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hidden = SettingsScope.of(context).hideAmounts;
    final now = DateTime.now();
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: muted))), Text(value)]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.name), actions: [
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            c.deleteSubscription(id);
            Navigator.of(context).pop();
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        row('Amount', _price(s, hidden)),
        row('Renews', s.cycle.label),
        if (s.nextRenewal != null) row('Next renewal', dateLabel(s.nextRenewal!, withTime: false)),
        if (s.lastPaid != null) row('Last paid', dateLabel(s.lastPaid!, withTime: false)),
        row('Status', s.status == SubStatus.active ? 'Active' : 'Cancelled'),
        if (s.failedRecently)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('The last charge failed (not enough money). The service may cancel or retry it.',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (s.missed(now))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No payment arrived after the renewal date. Did you cancel it?', style: TextStyle(color: muted)),
          ),
        const SizedBox(height: 8),
        s.status == SubStatus.active
            ? OutlinedButton(onPressed: () => c.setSubscriptionStatus(id, SubStatus.cancelled), child: const Text('I cancelled it'))
            : OutlinedButton(onPressed: () => c.setSubscriptionStatus(id, SubStatus.active), child: const Text('It is active again')),
        const SizedBox(height: 16),
        Text('Payments', style: theme.textTheme.titleMedium),
        if (s.payments.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('None found yet.', style: TextStyle(color: muted))),
        for (final t in s.payments.reversed)
          TxTile(t, margin: ItemCard.inPadded, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxDetailScreen(t.id)))),
      ]),
    );
  }
}

/// A subscription paid some other way (for example by mobile money).
class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  Cycle _cycle = Cycle.monthly;
  Provider _account = Provider.mtn;
  final _periods = TextEditingController(text: '1');
  DateTime _paidOn = DateTime.now();

  /// How many cycles I paid for at once (1 to 120).
  int? get _count {
    final v = int.tryParse(_periods.text.trim());
    return v == null || v < 1 || v > 120 ? null : v;
  }

  DateTime get _expires {
    var d = DateTime(_paidOn.year, _paidOn.month, _paidOn.day);
    for (var i = 0; i < (_count ?? 1); i++) {
      d = _cycle.after(d);
    }
    return d;
  }

  int? get _minor {
    final v = int.tryParse(_amount.text.replaceAll(RegExp(r'[ ,]'), ''));
    return v == null || v <= 0 ? null : v * 100;
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty && _minor != null && _count != null;
    final unit = switch (_cycle) { Cycle.weekly => 'Weeks', Cycle.monthly => 'Months', Cycle.yearly => 'Years' };
    final end = _expires;
    final monthAhead = DateTime(end.year, end.month - 1, end.day).isAfter(_paidOn);
    return Scaffold(
      appBar: AppBar(title: const Text('Add subscription')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name', helperText: 'Use the merchant name from the messages so payments are found', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (RWF)', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        SegmentedButton<Cycle>(
          segments: [for (final c in Cycle.values) ButtonSegment(value: c, label: Text(c.label))],
          selected: {_cycle},
          onSelectionChanged: (s) => setState(() => _cycle = s.single),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          for (final p in Provider.values)
            ChoiceChip(label: Text(p.short), selected: _account == p, showCheckmark: false, onSelected: (_) => setState(() => _account = p)),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Paid on'),
          subtitle: Text(dateLabel(_paidOn, withTime: false)),
          trailing: TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _paidOn, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) setState(() => _paidOn = d);
            },
            child: const Text('Change'),
          ),
        ),
        TextField(
          controller: _periods,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '$unit paid',
            border: const OutlineInputBorder(),
            errorText: _count == null ? 'Enter a number from 1 to 120' : null,
            helperText: 'Runs out ${dateLabel(end, withTime: false)}. '
                'Reminder a day before${monthAhead ? ' and a month before' : ''}.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: !canSave
              ? null
              : () {
                  LedgerScope.of(context).addSubscription(
                      name: _name.text.trim(), amount: _minor!, cycle: _cycle, account: _account, nextRenewal: end, paidFrom: _paidOn);
                  Navigator.of(context).pop();
                },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
