import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/ledger_controller.dart';
import '../platform/leaving_app.dart';
import '../platform/pdf_text.dart';
import '../widgets/tx_widgets.dart';

/// Import an MTN MoMo or Equity statement PDF to find what the alerts missed
/// (spec: Statement Import). The PDF is read on the phone; nothing is uploaded
/// except the parsed rows that get added.
class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({super.key});

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  bool _busy = false;
  String? _error;
  ImportSummary? _summary;
  String? _file;

  Future<void> _pick() async {
    final c = LedgerScope.of(context);
    expectExternal();
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final file = picked.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _summary = null;
      _file = file.name;
    });
    try {
      final lines = await const PdfTextReader().lines(path);
      final summary = c.importStatement(lines);
      setState(() {
        _summary = summary;
        if (summary == null) _error = 'This does not look like a MoMo statement or an Equity account statement.';
      });
    } on PdfPasswordException {
      setState(() => _error = 'This PDF has a password. Open it once, save a copy without one, and import that.');
    } catch (e) {
      setState(() => _error = 'Could not read this PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = _summary;
    final since = LedgerScope.of(context).trackingSince;
    Widget line(String label, int n) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [Expanded(child: Text(label)), Text('$n', style: const TextStyle(fontWeight: FontWeight.w600))]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Import a statement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pick an MTN MoMo statement or an Equity Bank account statement (PDF). The app finds transactions the alerts '
            'missed and adds them as "From statement". Importing the same statement twice adds nothing new.',
            style: TextStyle(color: muted),
          ),
          if (since != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Only transactions from ${dateLabel(since, withTime: false)} on are used, the day FinTrack was installed. '
                'Earlier rows in the statement are skipped.',
                style: TextStyle(color: muted),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Choose PDF')),
          const SizedBox(height: 24),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (s != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_file ?? 'Statement', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  line('Rows read', s.rows),
                  if (s.skippedBefore > 0 && s.since != null)
                    line('Skipped, before ${dateLabel(s.since!, withTime: false)}', s.skippedBefore),
                  line('Already known', s.known),
                  line('Added', s.added),
                  line('Transfers confirmed', s.transfersConfirmed),
                  line('Foreign amounts filled', s.foreignFilled),
                  if (s.feesFixed > 0) line('Fees completed', s.feesFixed),
                  line('Balance mismatches closed', s.mismatchesClosed),
                  if (s.added > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('New expenses and income wait in Review for a category.', style: TextStyle(color: muted)),
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
