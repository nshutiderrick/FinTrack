import 'package:flutter/material.dart';

import '../data/ledger_controller.dart';

/// Add, rename and delete categories. A rename also changes past
/// transactions; only an unused category can be deleted.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<String?> _ask(BuildContext context, String title, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    final theme = Theme.of(context);

    List<Widget> group(String title, List<String> items, bool income) => [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () async {
                  final name = await _ask(context, 'New category');
                  if (name == null || name.isEmpty) return;
                  if (items.any((i) => i.toLowerCase() == name.toLowerCase())) return;
                  c.setCategories(income: income, list: [...items, name]);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ]),
          ),
          for (final cat in items)
            Builder(builder: (context) {
              final uses = c.categoryUses(cat, income: income);
              return ListTile(
                title: Text(cat),
                subtitle: Text(uses == 0 ? 'Not used' : '$uses transaction${uses == 1 ? '' : 's'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await _ask(context, 'Rename category', initial: cat);
                      if (name == null || name.isEmpty || name == cat) return;
                      c.renameCategory(cat, name, income: income);
                    },
                  ),
                  // A used category can only be renamed, so its transactions keep one.
                  IconButton(
                    tooltip: uses == 0 ? 'Delete' : 'In use, rename it instead',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: uses > 0 ? null : () => c.deleteCategory(cat, income: income),
                  ),
                ]),
              );
            }),
        ];

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ...group('Spending', c.expenseCategories, false),
        ...group('Income', c.incomeCategories, true),
      ]),
    );
  }
}
