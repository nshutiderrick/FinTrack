import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/ledger.dart';
import '../core/loans.dart';
import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../platform/cloudinary.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';

/// Everything about one transaction, and what I can change: category,
/// description, photo, lending. Manual entries can also be deleted.
class TxDetailScreen extends StatefulWidget {
  const TxDetailScreen(this.id, {super.key, this.uploader});

  final String id;
  final CloudinaryUploader? uploader;

  @override
  State<TxDetailScreen> createState() => _TxDetailScreenState();
}

class _TxDetailScreenState extends State<TxDetailScreen> {
  final _description = TextEditingController();
  bool _uploading = false;
  String? _shownDescriptionFor;

  Future<void> _addPhoto(ImageSource source) async {
    final c = LedgerScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await pickExpensePhoto(source);
    if (bytes == null) return;
    setState(() => _uploading = true);
    try {
      final photo = await (widget.uploader ?? CloudinaryUploader()).upload(bytes);
      c.setPhoto(widget.id, photo.secureUrl, photo.publicId);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Photo upload failed. Check the connection and try again.')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _lend(Tx tx) async {
    final c = LedgerScope.of(context);
    final r = await showLendSheet(context, person: tx.title);
    if (r == null) return;
    c.lendFromTx(tx, due: r.due, note: r.note);
  }

  Future<void> _linkRepayment(Tx tx, List<Loan> loans) async {
    final c = LedgerScope.of(context);
    final loan = await showModalBottomSheet<Loan>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(shrinkWrap: true, children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Which loan does this repay?')),
        for (final l in loans)
          ListTile(
            title: Text(l.who),
            subtitle: Text('Lent ${dateLabel(l.openedAt, withTime: false)}'),
            trailing: l.left == null ? null : Amount(l.left!),
            onTap: () => Navigator.of(context).pop(l),
          ),
      ]),
    );
    if (loan != null) c.linkToLoan(tx.id, loan.id);
  }

  Future<void> _delete() async {
    final c = LedgerScope.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It is removed from your reports and balances. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      c.deleteManual(widget.id);
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final tx = c.ledger.txs.where((t) => t.id == widget.id).firstOrNull;
    if (tx == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This transaction is no longer here.')));
    }
    if (_shownDescriptionFor != tx.record.description) {
      _shownDescriptionFor = tx.record.description;
      _description.text = tx.record.description ?? '';
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hidden = SettingsScope.of(context).hideAmounts;
    final m = tx.m;
    final sign = m.direction == Direction.inflow ? 1 : -1;
    final loan = tx.record.loanLink == null ? null : c.loans.byId(tx.record.loanLink!);
    final openOwedToMe = c.loans.owedToMe.where((l) => !l.closed).toList();

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: TextStyle(color: muted))),
            Expanded(child: Text(value)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (tx.record.source == TxSource.manual)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(tx.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          m.rwfKnown || !tx.approximate
              ? Amount(sign * tx.rwf, signed: true, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))
              : Text('${m.currency} ${(m.amount / 100).toStringAsFixed(2)}', style: theme.textTheme.headlineMedium),
          if (tx.cancelled) Text('Reversed: not counted', style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          if (tx.isExpense || tx.isIncome)
            Card(
              child: ListTile(
                title: Text(loan != null ? 'Loan' : (tx.category ?? 'Pick a category')),
                subtitle: Text(loan != null ? 'Not counted as ${tx.isExpense ? 'spending' : 'income'}' : 'Category'),
                trailing: loan != null ? null : const Icon(Icons.chevron_right),
                onTap: loan != null ? null : () => showCategorySheet(context, tx),
              ),
            ),
          if (loan != null)
            Card(
              child: ListTile(
                title: Text(loan.side == LoanSide.owedToMe ? '${loan.who} owes me' : 'I owe ${loan.who}'),
                subtitle: Text(loan.left == null ? 'Part of this loan' : 'Still to pay: ${formatRwf(loan.left!, hidden: hidden)}'),
                trailing: TextButton(onPressed: () => c.unlinkLoan(tx.id), child: const Text('Unlink')),
              ),
            )
          else if (tx.isExpense && m.isPerson)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => _lend(tx), icon: const Icon(Icons.handshake_outlined), label: const Text('I lent this')),
            )
          else if (m.direction == Direction.inflow && m.isPerson && openOwedToMe.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _linkRepayment(tx, openOwedToMe),
                icon: const Icon(Icons.link),
                label: const Text('This repays a loan'),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            decoration: InputDecoration(
              labelText: 'Description',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Save description',
                icon: const Icon(Icons.check),
                onPressed: () {
                  c.setDescription(tx.id, _description.text);
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            onSubmitted: (v) => c.setDescription(tx.id, v),
          ),
          const SizedBox(height: 16),
          Text('Photo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (tx.record.photoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(tx.record.photoUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(16), child: Text('Photo could not load.'))),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => c.removePhoto(tx.id), child: const Text('Remove photo')),
            ),
          ] else if (_uploading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Camera')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_outlined), label: const Text('Gallery')),
              ),
            ]),
          const SizedBox(height: 16),
          Text('Details', style: theme.textTheme.titleMedium),
          row('Account', tx.provider.label),
          row('Date', dateLabel(tx.time)),
          if (m.fee > 0) row('Fee', formatRwf(m.fee, hidden: hidden)),
          if (!m.rwfKnown) row('Charged', '${m.currency} ${(m.amount / 100).toStringAsFixed(2)}'),
          if (!m.rwfKnown && tx.foreignRwf != null) row('In RWF', formatRwf(tx.foreignRwf!, hidden: hidden)),
          if (m.balance != null)
            row('Balance after', tx.balanceNotShown ? 'Not shown in the message' : formatRwf(m.balance!, hidden: hidden)),
          if (tx.balanceNotShown && tx.balanceAfter != null)
            row('Expected balance', formatRwf(tx.balanceAfter!, hidden: hidden)),
          if (m.phone != null) row('Phone', m.phone!),
          if (m.reference != null && !m.reference!.startsWith('AUTH')) row('Reference', m.reference!),
          row('From', switch (tx.record.source) {
            TxSource.alert => 'Alert',
            TxSource.statement => 'Statement import',
            TxSource.manual => 'Added by hand',
          }),
        ],
      ),
    );
  }
}

class LendDetails {
  const LendDetails(this.due, this.note);
  final DateTime? due;
  final String? note;
}

/// After "I lent this": optional due date and note (spec: Lent details).
Future<LendDetails?> showLendSheet(BuildContext context, {required String person}) {
  DateTime? due;
  final note = TextEditingController();
  return showModalBottomSheet<LendDetails>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lent to $person', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('It still leaves your balance, but is not counted as spending.'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Due date (optional)'),
            subtitle: Text(due == null ? 'None' : dateLabel(due!, withTime: false)),
            trailing: TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime(2100));
                if (d != null) setState(() => due = d);
              },
              child: const Text('Set'),
            ),
          ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, LendDetails(due, note.text.trim().isEmpty ? null : note.text.trim())),
            child: const Text('Save loan'),
          ),
        ]),
      ),
    ),
  );
}
