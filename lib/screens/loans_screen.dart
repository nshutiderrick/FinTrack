import 'package:flutter/material.dart';

import '../core/ledger.dart';
import '../core/loans.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';
import '../widgets/glass.dart';
import '../widgets/page_header.dart';
import 'subscriptions_screen.dart';
import 'tx_detail_screen.dart';

/// Dues: loans and subscriptions, as two tabs of one page.
class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const PageHeader('Dues'),
        const TabBar(tabs: [Tab(text: 'Loans'), Tab(text: 'Subscriptions')]),
        const Expanded(child: TabBarView(children: [LoansScreen(), SubscriptionsScreen()])),
      ]),
    );
  }
}

/// Money I owe and money owed to me (spec: Loans), the first tab of Dues.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  LoanSide _side = LoanSide.iOwe;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final book = c.loans;
    final now = DateTime.now();
    final theme = Theme.of(context);
    final overdue = book.overdueCount(now);
    return Scaffold(
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: kBottomBarClearance),
          child: FloatingActionButton.extended(
            heroTag: 'addLoan',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddLoanScreen())),
            icon: const Icon(Icons.add),
            label: const Text('Add loan'),
          ),
        ),
        body: Column(children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  _total(context, 'I owe', book.totalLeft(LoanSide.iOwe)),
                  _total(context, 'Owed to me', book.totalLeft(LoanSide.owedToMe)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Overdue', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                      Text('$overdue', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<LoanSide>(
                segments: const [
                  ButtonSegment(value: LoanSide.iOwe, label: Text('I owe')),
                  ButtonSegment(value: LoanSide.owedToMe, label: Text('Owed to me')),
                ],
                selected: {_side},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _side = s.single),
              ),
            ),
          ),
          Expanded(
            child: _side == LoanSide.iOwe
                ? _LoanList(book.iOwe,
                    unlinked: book.unlinked, empty: 'No loans. App loans (MoFaya, MoFlex, Mokash) appear here from their messages.')
                : _LoanList(book.owedToMe, empty: 'Nobody owes you. Use "I lent this" on money you sent someone, or add a loan.'),
          ),
        ]),
    );
  }

  static Widget _total(BuildContext context, String label, int v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          Amount(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _LoanList extends StatelessWidget {
  const _LoanList(this.loans, {required this.empty, this.unlinked = const []});
  final List<Loan> loans;
  final List<Tx> unlinked;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final open = loans.where((l) => !l.closed).toList();
    final closed = loans.where((l) => l.closed).toList();
    if (loans.isEmpty && unlinked.isEmpty) {
      return Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: muted)));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
      for (final l in open) _LoanTile(l),
      if (closed.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Closed', style: TextStyle(color: muted))),
        for (final l in closed) _LoanTile(l),
      ],
      if (unlinked.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Repayments not tied to a loan', style: TextStyle(color: muted)),
        ),
        for (final t in unlinked)
          TxTile(t, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxDetailScreen(t.id)))),
      ],
    ]);
  }
}

class _LoanTile extends StatelessWidget {
  const _LoanTile(this.l);
  final Loan l;

  @override
  Widget build(BuildContext context) {
    final hidden = SettingsScope.of(context).hideAmounts;
    final overdue = l.overdue(DateTime.now());
    final parts = <String>[
      dateLabel(l.openedAt, withTime: false),
      if (l.fromApp) 'App loan',
      if (l.due != null) 'due ${dateLabel(l.due!, withTime: false)}',
      if (overdue) 'OVERDUE',
      if (l.repaid > 0) 'repaid ${formatRwf(l.repaid, hidden: hidden)}',
    ];
    return ItemCard(
        child: ListTile(
      title: Text(l.who, style: TextStyle(fontWeight: overdue ? FontWeight.bold : null)),
      subtitle: Text(parts.join(' · ')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Amount(l.borrowed, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(l.closed ? 'Closed' : (l.left == null ? 'open' : '${formatRwf(l.left!, hidden: hidden)} left'),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(l.id))),
    ));
  }
}

class LoanDetailScreen extends StatelessWidget {
  const LoanDetailScreen(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final l = c.loans.byId(id);
    if (l == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This loan is no longer here.')));
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: muted))), value]),
        );
    void open(String txId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxDetailScreen(txId)));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.side == LoanSide.iOwe ? 'I owe ${l.who}' : '${l.who} owes me'),
        actions: [
          if (!l.fromApp)
            IconButton(
              tooltip: 'Delete loan',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete this loan?'),
                    content: const Text('Its payments go back to being normal transactions. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  c.deleteLoan(l);
                  nav.pop();
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        row('Amount', Amount(l.borrowed)),
        if (l.totalToRepay != null) row('Total to repay', Amount(l.totalToRepay!)),
        row('Repaid so far', Amount(l.repaid)),
        row('Still to pay', l.closed ? const Text('Nothing, closed') : (l.left == null ? const Text('Shown when the lender closes it') : Amount(l.left!))),
        row('Started', Text(dateLabel(l.openedAt, withTime: false))),
        if (l.due != null) row('Due', Text(dateLabel(l.due!, withTime: false))),
        if (l.note != null) row('Note', Text(l.note!)),
        if (!l.fromApp && !l.closed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(onPressed: () => c.closeLoan(l.id), child: const Text('Mark as paid back')),
          ),
        const SizedBox(height: 16),
        if (l.source != null) ...[
          Text(l.side == LoanSide.iOwe ? 'Money received' : 'Money sent', style: theme.textTheme.titleMedium),
          TxTile(l.source!, margin: ItemCard.inPadded, onTap: () => open(l.source!.id)),
        ],
        const SizedBox(height: 8),
        Text('Repayments', style: theme.textTheme.titleMedium),
        if (l.payments.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('None yet.', style: TextStyle(color: muted))),
        for (final t in l.payments.reversed) TxTile(t, margin: ItemCard.inPadded, onTap: () => open(t.id)),
        if (l.side == LoanSide.owedToMe)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('When they send money back, open that payment and choose "This repays a loan".',
                style: TextStyle(color: muted, fontSize: 13)),
          ),
      ]),
    );
  }
}

/// A loan from or to someone, typed in by hand (for cash, or a friend's loan).
class AddLoanScreen extends StatefulWidget {
  const AddLoanScreen({super.key});

  @override
  State<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends State<AddLoanScreen> {
  LoanSide _side = LoanSide.owedToMe;
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _total = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime? _due;

  static int? _minor(String s) {
    final v = int.tryParse(s.replaceAll(RegExp(r'[ ,]'), ''));
    return v == null || v <= 0 ? null : v * 100;
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _person.text.trim().isNotEmpty && _minor(_amount.text) != null;
    Future<DateTime?> pick(DateTime initial) =>
        showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    return Scaffold(
      appBar: AppBar(title: const Text('Add loan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<LoanSide>(
          segments: const [
            ButtonSegment(value: LoanSide.owedToMe, label: Text('I lent')),
            ButtonSegment(value: LoanSide.iOwe, label: Text('I borrowed')),
          ],
          selected: {_side},
          onSelectionChanged: (s) => setState(() => _side = s.single),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _person,
          decoration: InputDecoration(labelText: _side == LoanSide.iOwe ? 'Lender' : 'Who owes me', border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (RWF)', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        if (_side == LoanSide.iOwe) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _total,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Total to repay, with interest (optional)', border: OutlineInputBorder()),
          ),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Date'),
          subtitle: Text(dateLabel(_date, withTime: false)),
          trailing: TextButton(
              onPressed: () async {
                final d = await pick(_date);
                if (d != null) setState(() => _date = d);
              },
              child: const Text('Change')),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Due date (optional)'),
          subtitle: Text(_due == null ? 'None' : dateLabel(_due!, withTime: false)),
          trailing: TextButton(
              onPressed: () async {
                final d = await pick(_due ?? DateTime.now());
                if (d != null) setState(() => _due = d);
              },
              child: const Text('Set')),
        ),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Text('This only records the loan. Payments made through MoMo, Airtel or Equity can be linked to it from the payment.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: !canSave
              ? null
              : () {
                  LedgerScope.of(context).addLoan(
                    side: _side,
                    person: _person.text.trim(),
                    amount: _minor(_amount.text)!,
                    totalToRepay: _side == LoanSide.iOwe ? _minor(_total.text) : null,
                    createdAt: _date,
                    due: _due,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  );
                  Navigator.of(context).pop();
                },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
