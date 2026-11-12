import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../core/ledger.dart';
import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../screens/tx_detail_screen.dart';
import '../settings.dart';
import 'amount.dart';

String dateLabel(DateTime t, {bool withTime = true}) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final d = day == today
      ? 'Today'
      : day == today.subtract(const Duration(days: 1))
          ? 'Yesterday'
          : '${t.day}/${t.month}/${t.year}';
  return withTime ? '$d $hm' : d;
}

/// "All accounts / Equity / MTN / Airtel / Cash", remembered across screens.
class AccountFilterBar extends StatelessWidget {
  const AccountFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    Widget chip(String label, Provider? p) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: settings.account == p,
            onSelected: (_) => settings.account = p,
            showCheckmark: false,
          ),
        );
    // Hidden accounts are not offered; "All accounts" means all visible ones.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(settings.hidden.isEmpty ? 'All accounts' : 'All shown', null),
        for (final p in settings.visibleAccounts) chip(p.short, p),
      ]),
    );
  }
}

/// A list item as a card: transactions, loans and subscriptions all use it.
/// [margin] leaves the side gap to the list when the list has no padding of its own.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.child, this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4)});

  /// For lists that already pad their sides.
  static const inPadded = EdgeInsets.symmetric(vertical: 4);

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) =>
      Card(margin: margin, clipBehavior: Clip.antiAlias, child: child);
}

/// One transaction, as a card. Money out is shown with a minus, money in with
/// a plus. Tapping it opens the transaction's detail screen unless [onTap] is
/// given. [card] false gives the bare row, for use inside another card.
class TxTile extends StatelessWidget {
  const TxTile(this.tx, {super.key, this.onTap, this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4), this.card = true});

  final Tx tx;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final m = tx.m;
    final sign = m.direction == Direction.inflow ? 1 : -1;
    final tags = <String>[
      tx.provider.short,
      dateLabel(tx.time),
      // A category only means something for spending and income (not transfers or loans).
      if ((tx.isExpense || tx.isIncome) && !tx.isLoan) ?tx.category,
      if (tx.needsCategory) 'Pending',
      if (tx.kind == Kind.transfer) 'Transfer',
      if (tx.isLoan) 'Loan',
      if (tx.record.photoUrl != null) 'Photo',
      if (tx.cancelled) 'Reversed',
      if (tx.record.source == TxSource.statement) 'From statement',
      if (tx.record.source == TxSource.manual) 'Added by hand',
    ];
    final foreign = !m.rwfKnown;
    final row = ListTile(
      onTap: onTap ?? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxDetailScreen(tx.id))),
      title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(tags.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (foreign && tx.approximate)
            Text('${sign < 0 ? '- ' : '+ '}${m.currency} ${(m.amount / 100).toStringAsFixed(2)}',
                style: TextStyle(
                    fontWeight: FontWeight.w600, decoration: tx.cancelled ? TextDecoration.lineThrough : null))
          else
            Amount(sign * tx.rwf,
                signed: true,
                style: TextStyle(
                    fontWeight: FontWeight.w600, decoration: tx.cancelled ? TextDecoration.lineThrough : null)),
          if (m.fee > 0) Text('fee ${formatRwf(m.fee, hidden: SettingsScope.of(context).hideAmounts)}',
              style: TextStyle(color: muted, fontSize: 12)),
          if (foreign && !tx.approximate)
            Text('${m.currency} ${(m.amount / 100).toStringAsFixed(2)}', style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
    return card ? ItemCard(margin: margin, child: row) : row;
  }
}

/// After "Between my accounts": also remember the other side as mine? Returns
/// true or false, or null if dismissed. Nothing to remember: false at once.
Future<bool?> _askRemember(BuildContext context, Tx tx) async {
  final name = tx.m.counterparty;
  final phone = tx.m.phone;
  final hasName = name != null && name.trim().isNotEmpty && tx.m.isPerson;
  final hasPhone = phone != null && phone.replaceAll(RegExp(r'\D'), '').length >= 9;
  if (!hasName && !hasPhone) return false;
  final what = [if (hasName) '"$name"', if (hasPhone) 'the number $phone'].join(' and ');
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remember as yours?'),
      content: Text('Save $what as yours, so the next transfer like this is caught on its own? '
          'You can change it in Settings → My names and accounts.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Just this one')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, remember')),
      ],
    ),
  );
}

/// Picks a category for an expense or income, with an optional description.
/// The parser's hint is offered first, but nothing is saved until I tap one.
Future<void> showCategorySheet(BuildContext context, Tx tx) {
  final ledger = LedgerScope.of(context);
  final income = tx.m.direction == Direction.inflow;
  final options = income ? ledger.incomeCategories : ledger.expenseCategories;
  final hint = suggestedCategory(tx.m.categoryHint);
  final ordered = [?hint, ...options.where((c) => c != hint)];
  final description = TextEditingController(text: tx.record.description);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Row(children: [
            Amount(tx.rwf, style: Theme.of(context).textTheme.titleMedium),
            Text('  ·  ${tx.provider.label}  ·  ${dateLabel(tx.time)}'),
          ]),
          const SizedBox(height: 12),
          // For a transfer the app did not catch (my own money moving between my accounts).
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Between my accounts'),
              onPressed: () async {
                final nav = Navigator.of(context);
                final remember = await _askRemember(context, tx);
                if (remember == null) return; // dismissed
                if (description.text.trim().isNotEmpty) ledger.setDescription(tx.id, description.text);
                ledger.markAsTransfer(tx, remember: remember);
                nav.pop();
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Text(income ? 'Income category' : 'Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ordered)
                    ActionChip(
                      label: Text(c),
                      onPressed: () {
                        ledger.setCategory(tx.id, c, description: description.text);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
          ),
        ],
      ),
    ),
  );
}
