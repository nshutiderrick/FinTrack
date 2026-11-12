import 'package:flutter/material.dart';

import '../core/models.dart';
import '../data/ledger_controller.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';

/// Adds an income or expense by hand (cash, or what a balance gap shows was missed).
/// Saved with its category straight away, so it skips Pending.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, this.account, this.time, this.gap});

  final Provider? account;
  final DateTime? time;

  /// When opened from a balance mismatch: the unexplained amount (negative is money missing).
  final int? gap;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late Provider _account = widget.account ?? Provider.cash;
  late bool _income = (widget.gap ?? -1) > 0;
  late DateTime _time = widget.time ?? DateTime.now();
  String? _category;
  final _amount = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.gap != null) _amount.text = (widget.gap!.abs() / 100).round().toString();
  }

  int? get _minor {
    final v = int.tryParse(_amount.text.replaceAll(RegExp(r'[ ,]'), ''));
    return v == null || v <= 0 ? null : v * 100;
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(context: context, initialDate: _time, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
    setState(() => _time = DateTime(d.year, d.month, d.day, t?.hour ?? _time.hour, t?.minute ?? _time.minute));
  }

  void _save() {
    LedgerScope.of(context).addManual(
      account: _account,
      income: _income,
      amount: _minor!,
      time: _time,
      category: _category!,
      description: _description.text,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = LedgerScope.of(context);
    final categories = _income ? ledger.incomeCategories : ledger.expenseCategories;
    final canSave = _minor != null && _category != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Add entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.gap != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Unexplained: ${formatRwf(widget.gap!)}. Entries dated before the message reduce it.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Expense')),
              ButtonSegment(value: true, label: Text('Income')),
            ],
            selected: {_income},
            onSelectionChanged: (s) => setState(() {
              _income = s.single;
              _category = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (RWF)', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Account', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in Provider.values)
              ChoiceChip(
                label: Text(p.short),
                selected: _account == p,
                showCheckmark: false,
                onSelected: (_) => setState(() => _account = p),
              ),
          ]),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date and time'),
            subtitle: Text(dateLabel(_time)),
            trailing: TextButton(onPressed: _pickTime, child: const Text('Change')),
          ),
          Text('Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in categories)
              ChoiceChip(
                label: Text(c),
                selected: _category == c,
                showCheckmark: false,
                onSelected: (_) => setState(() => _category = c),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: canSave ? _save : null, child: const Text('Save')),
        ],
      ),
    );
  }
}
