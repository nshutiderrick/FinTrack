import 'package:flutter/material.dart';

import '../core/loans.dart';
import '../core/people.dart';
import '../data/ledger_controller.dart';
import '../settings.dart';
import '../widgets/amount.dart';
import '../widgets/tx_widgets.dart';
import 'tx_detail_screen.dart';

/// Everyone I sent money to or received money from (spec: People Tracking).
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final people = LedgerScope.of(context).people;
    final hidden = SettingsScope.of(context).hideAmounts;
    final q = _query.toUpperCase();
    final shown = q.isEmpty
        ? people
        : people.where((p) => p.name.toUpperCase().contains(q) || p.messageName.toUpperCase().contains(q) || (p.phone ?? '').contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('People appear here once you send or receive money from someone.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        for (final p in shown)
          ListTile(
            title: Text(p.name),
            subtitle: Text([
              if (p.nickname != null) p.messageName,
              'sent ${formatRwf(p.sent, hidden: hidden)}',
              'received ${formatRwf(p.received, hidden: hidden)}',
            ].join(' · ')),
            trailing: Text(dateLabel(p.last, withTime: false)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonScreen(p.key))),
          ),
      ]),
    );
  }
}

class PersonScreen extends StatelessWidget {
  const PersonScreen(this.personKey, {super.key});
  final String personKey;

  Future<void> _rename(BuildContext context, Person p) async {
    final c = LedgerScope.of(context);
    final ctl = TextEditingController(text: p.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nickname'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: p.messageName, helperText: 'For example Mom or Landlord. Leave empty to use the name from messages.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) c.setNickname(p.key, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final p = c.people.where((x) => x.key == personKey).firstOrNull;
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nobody here.')));
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final upper = p.name.toUpperCase();
    final loans = [...c.loans.iOwe, ...c.loans.owedToMe]
        .where((l) => !l.closed && (l.who.toUpperCase() == upper || l.who.toUpperCase() == p.messageName.toUpperCase()))
        .toList();
    Widget stat(String label, Widget v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: muted, fontSize: 12)),
            v,
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(p.name), actions: [
        IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(context, p)),
      ]),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text([if (p.nickname != null) p.messageName, ?p.phone].join(' · '), style: TextStyle(color: muted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                stat('Sent', Amount(p.sent, style: const TextStyle(fontWeight: FontWeight.w600))),
                stat('Received', Amount(p.received, style: const TextStyle(fontWeight: FontWeight.w600))),
                stat('Payments', Text('${p.txs.length}', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ),
        for (final l in loans)
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: Text(l.side == LoanSide.owedToMe ? 'Owes me' : 'I owe'),
            trailing: Amount(l.left ?? l.borrowed - l.repaid),
          ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('History', style: theme.textTheme.titleMedium)),
        for (final t in p.txs)
          TxTile(t, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxDetailScreen(t.id)))),
      ]),
    );
  }
}
