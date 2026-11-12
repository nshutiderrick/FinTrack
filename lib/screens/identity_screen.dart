import 'package:flutter/material.dart';

import '../core/own_accounts.dart';
import '../data/ledger_controller.dart';

/// Shown right after sign-in until I have saved at least one name and one
/// account. Without them, money between my own accounts would look like
/// spending and income, so the dashboard waits.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: IdentityForm(
          header: [
            Text('Before you start', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Add your own names and accounts. Money sent between them is a transfer, '
              'not spending or income. They stay in your private account.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          saveLabel: 'Continue',
        ),
      ),
    );
  }
}

/// The same form, from Settings.
class IdentityScreen extends StatelessWidget {
  const IdentityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My names and accounts')),
      body: IdentityForm(
        header: [
          Text('Money sent to or received from these is a transfer between your accounts.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        saveLabel: 'Save',
        popOnSave: true,
      ),
    );
  }
}

class _AccountRow {
  _AccountRow(this.type, String number) : number = TextEditingController(text: number);
  AccountType type;
  final TextEditingController number;
}

/// Names and accounts, one per row, with "Add another" for each.
class IdentityForm extends StatefulWidget {
  const IdentityForm({super.key, required this.header, required this.saveLabel, this.popOnSave = false});

  final List<Widget> header;
  final String saveLabel;
  final bool popOnSave;

  @override
  State<IdentityForm> createState() => _IdentityFormState();
}

class _IdentityFormState extends State<IdentityForm> {
  late final LedgerController _c = LedgerScope.of(context);
  late final List<TextEditingController> _names = [
    for (final n in _c.ownNames.isEmpty ? [''] : _c.ownNames) TextEditingController(text: n),
  ];
  late final List<_AccountRow> _accounts = [
    for (final a in _c.ownAccounts) _AccountRow(a.type, a.number),
    if (_c.ownAccounts.isEmpty) _AccountRow(AccountType.mtn, ''),
  ];
  bool _tried = false;

  List<String> get _cleanNames => [for (final n in _names) if (n.text.trim().isNotEmpty) n.text.trim()];

  List<OwnAccount> get _cleanAccounts => [
        for (final a in _accounts)
          if (a.type.check(a.number.text) == null) OwnAccount(a.type, a.number.text.replaceAll(RegExp(r'\D'), '')),
      ];

  bool get _rowsValid => _accounts.every((a) => a.number.text.trim().isEmpty || a.type.check(a.number.text) == null);
  bool get _valid => _cleanNames.isNotEmpty && _cleanAccounts.isNotEmpty && _rowsValid;

  void _save() {
    setState(() => _tried = true);
    if (!_valid) return;
    _c.saveIdentity(names: _cleanNames, accounts: _cleanAccounts);
    if (widget.popOnSave) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final n in _names) {
      n.dispose();
    }
    for (final a in _accounts) {
      a.number.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Spellings seen on both sides of a transfer, offered with one tap.
    final seen = _c.suggestedNames.where((s) => !_names.any((n) => n.text.trim() == s)).toList();
    Widget remove(VoidCallback onTap) => IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: onTap);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...widget.header,
        const SizedBox(height: 24),
        Text('My names', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('As they appear in messages. Word order and capitals do not matter, so add each different spelling once.',
            style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 12),
        for (final (i, n) in _names.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: n,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Name ${i + 1}',
                    border: const OutlineInputBorder(),
                    errorText: _tried && i == 0 && _cleanNames.isEmpty ? 'Add at least one name' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_names.length > 1) remove(() => setState(() => _names.removeAt(i).dispose())),
            ]),
          ),
        if (seen.isNotEmpty) ...[
          Text('Seen in your messages', style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in seen)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(s),
                onPressed: () => setState(() {
                  final empty = _names.where((n) => n.text.trim().isEmpty).firstOrNull;
                  empty != null ? empty.text = s : _names.add(TextEditingController(text: s));
                }),
              ),
          ]),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _names.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Add another name'),
          ),
        ),
        const SizedBox(height: 16),
        Text('My accounts', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Each MoMo, Airtel and Equity account you own, one at a time.', style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 12),
        for (final (i, a) in _accounts.indexed)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 8, children: [
                      for (final t in AccountType.values)
                        ChoiceChip(
                          label: Text(switch (t) {
                            AccountType.mtn => 'MTN',
                            AccountType.airtel => 'Airtel',
                            AccountType.equity => 'Equity',
                          }),
                          selected: a.type == t,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => a.type = t),
                        ),
                    ]),
                  ),
                  if (_accounts.length > 1) remove(() => setState(() => _accounts.removeAt(i).number.dispose())),
                ]),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextField(
                    controller: a.number,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: a.type.label,
                      hintText: a.type.hint,
                      border: const OutlineInputBorder(),
                      errorText: a.number.text.trim().isNotEmpty
                          ? a.type.check(a.number.text)
                          : (_tried && i == 0 && _cleanAccounts.isEmpty ? 'Add at least one account' : null),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _accounts.add(_AccountRow(AccountType.mtn, ''))),
            icon: const Icon(Icons.add),
            label: const Text('Add another account'),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Text(widget.saveLabel)),
      ],
    );
  }
}
