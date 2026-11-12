import 'package:flutter/material.dart';

import '../data/ledger_controller.dart';

/// Erase all data and start again. Permanent, so it asks me to type ERASE.
class EraseScreen extends StatefulWidget {
  const EraseScreen({super.key});

  @override
  State<EraseScreen> createState() => _EraseScreenState();
}

class _EraseScreenState extends State<EraseScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;

  Future<void> _erase() async {
    final c = LedgerScope.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await c.eraseAll();
      nav.popUntil((r) => r.isFirst); // back to the start: setup comes up
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not erase. Check the connection and try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ready = _confirm.text.trim() == 'ERASE' && !_busy;
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(t))]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Erase all data')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Start again from today', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('This permanently deletes:'),
        const SizedBox(height: 8),
        bullet('every transaction, category you picked, description and photo link'),
        bullet('loans, subscriptions, nicknames and your own categories'),
        bullet('your names and accounts (you set them up again next)'),
        bullet('the alerts already read on this phone, so they are not added back'),
        const SizedBox(height: 8),
        Text(
          'It cannot be undone. Photos stay in Cloudinary. Appearance and hidden accounts are kept. '
          'New alerts are read from now on, and statement imports only use transactions from today.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _confirm,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Type ERASE to confirm', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: ready ? _erase : null,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Erase everything'),
        ),
      ]),
    );
  }
}
