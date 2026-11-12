// Local-only: reconciles real statement text (dumped from the PDFs) against the
// real SMS export. Skipped unless STATEMENT_TEXT_DIR points at a folder with
// momo.txt and/or equity.txt, and an sms-*.html export is in the project root.
//   STATEMENT_TEXT_DIR=... OWN_NAMES=... OWN_PHONES=... flutter test test/real_statement_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:expense_tracker/core/matcher.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/parser.dart';
import 'package:expense_tracker/core/reconcile.dart';
import 'package:expense_tracker/core/statement.dart';
import 'package:flutter_test/flutter_test.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _arrival(String s) {
  final x = RegExp(r'(\w{3}) (\d+), (\d{4}) (\d+):(\d\d):(\d\d) (AM|PM)').firstMatch(s)!;
  var h = int.parse(x[4]!) % 12;
  if (x[7] == 'PM') h += 12;
  return DateTime(int.parse(x[3]!), _months.indexOf(x[1]!) + 1, int.parse(x[2]!), h, int.parse(x[5]!), int.parse(x[6]!));
}

void main() {
  final env = Platform.environment;
  final dir = env['STATEMENT_TEXT_DIR'];
  final export = Directory.current.listSync().whereType<File>().where((f) => RegExp(r'sms-\d+\.html$').hasMatch(f.path)).firstOrNull;

  test('real statements against the real SMS history', () {
    final me = OwnIdentity(
      names: (env['OWN_NAMES'] ?? '').split(',').where((s) => s.isNotEmpty).toList(),
      phones: (env['OWN_PHONES'] ?? '').split(',').where((s) => s.isNotEmpty).toList(),
    );
    final parser = MessageParser(me);
    final html = export!.readAsStringSync();
    final parsed = RegExp(r"<tr><td>.*?</td><td>(.*?)</td><td>(.*?)</td><td[^>]*>(.*?)</td></tr>", dotAll: true)
        .allMatches(html)
        .map((r) => parser.parse(r[2]!, r[3]!.replaceAll('&amp;', '&').replaceAll('&#39;', "'"), _arrival(r[1]!)))
        .whereType<ParsedMessage>()
        .where((m) => m.kind != Kind.ignore && m.kind != Kind.failed && m.kind != Kind.loanInfo);
    final existing = TransactionMatcher().match(parsed);
    final reviewBefore = existing.where((t) => t.kind == Kind.needsReview).length;

    for (final name in ['momo.txt', 'equity.txt']) {
      final file = File('$dir/$name');
      if (!file.existsSync()) continue;
      final rows = StatementParser.parse(file.readAsLinesSync())!;
      final r = StatementReconciler(me).reconcile(rows, existing);
      final range = rows.isEmpty ? '' : '${rows.first.time} .. ${rows.last.time}';
      print('\n$name: ${rows.length} rows ($range)');
      print('  already known: ${r.known.length}');
      print('  missing (added): ${r.missing.length}');
      for (final m in r.missing.take(12)) {
        print('    ${m.time} ${m.direction.name} ${m.amount ~/ 100} RWF ${m.kind.name} "${m.counterparty}"');
      }
      print('  MoMo payments confirmed as transfers: ${r.confirmedTransfers.length}');
      print('  foreign card charges given an RWF amount: ${r.foreignAmounts.length}');
      for (final (t, rwf) in r.foreignAmounts.take(6)) {
        print('    ${t.message.counterparty} ${t.message.currency} ${t.message.amount / 100} = RWF ${rwf ~/ 100}');
      }
    }
    print('\nNeeds review before: $reviewBefore, after: ${existing.where((t) => t.kind == Kind.needsReview).length}');
  }, skip: dir == null || export == null ? 'set STATEMENT_TEXT_DIR and add an sms-*.html export' : false);
}
