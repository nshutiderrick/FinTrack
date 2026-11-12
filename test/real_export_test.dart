// Runs the full pipeline (parse -> match -> balance check) over a real
// SMS Backup & Restore HTML export, if one is in the project root. The export
// holds private data, so it is git-ignored and this test is skipped when it is
// missing. Own names/phones come from env vars:
//   OWN_NAMES="First Last" OWN_PHONES="07...,07..." flutter test test/real_export_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:expense_tracker/core/balance.dart';
import 'package:expense_tracker/core/matcher.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Nov 4, 2026 8:53:54 PM" -> DateTime.
DateTime _arrival(String s) {
  final x = RegExp(r'(\w{3}) (\d+), (\d{4}) (\d+):(\d\d):(\d\d) (AM|PM)').firstMatch(s)!;
  var h = int.parse(x[4]!) % 12;
  if (x[7] == 'PM') h += 12;
  return DateTime(int.parse(x[3]!), _months.indexOf(x[1]!) + 1, int.parse(x[2]!), h, int.parse(x[5]!), int.parse(x[6]!));
}

void main() {
  final export = Directory.current
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'sms-\d+\.html$').hasMatch(f.path))
      .firstOrNull;

  test('real export: parse, match and balance-check everything', () {
    final env = Platform.environment;
    final parser = MessageParser(OwnIdentity(
      names: (env['OWN_NAMES'] ?? '').split(',').where((s) => s.isNotEmpty).toList(),
      phones: (env['OWN_PHONES'] ?? '').split(',').where((s) => s.isNotEmpty).toList(),
    ));
    final html = export!.readAsStringSync();
    final rows = RegExp(r"<tr><td>.*?</td><td>(.*?)</td><td>(.*?)</td><td[^>]*>(.*?)</td></tr>", dotAll: true)
        .allMatches(html);

    final parsed = <ParsedMessage>[];
    final counts = <String, int>{};
    for (final r in rows) {
      final body = r[3]!.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
      final m = parser.parse(r[2]!, body, _arrival(r[1]!));
      if (m == null) continue;
      parsed.add(m);
      final key = '${m.provider.name}/${m.kind.name}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    print('PARSED\n${(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '  ${e.key}: ${e.value}').join('\n')}');

    final money = parsed.where((m) => m.kind != Kind.ignore && m.kind != Kind.failed && m.kind != Kind.loanInfo);
    final matched = TransactionMatcher().match(money);
    final review = matched.where((t) => t.kind == Kind.needsReview).toList();
    print('\nMATCHED: ${money.length} money messages -> ${matched.length} transactions '
        '(${money.length - matched.length} duplicates dropped)');
    print('  transfer pairs: ${matched.where((t) => t.kind == Kind.transfer && t.pair != null).length ~/ 2}');
    print('  transfers without a pair: ${matched.where((t) => t.kind == Kind.transfer && t.pair == null).length}');
    print('  cancelled by a reversal: ${matched.where((t) => t.cancelled).length}');
    print('  reversals with no match: ${matched.where((t) => t.kind == Kind.cancel && t.pair == null).length}');
    print('  still needs review: ${review.length}');
    for (final t in review) {
      print('    ${t.message.provider.name} ${t.message.time} ${t.message.amount ~/ 100} RWF -> ${t.message.counterparty}');
    }

    final tracker = BalanceTracker();
    final mismatches = <Provider, List<BalanceMismatch>>{};
    var resolved = 0;
    for (final t in matched.where((t) => t.movesMoney || t.message.balance != null)) {
      final r = tracker.apply(t.message);
      if (r is BalanceMismatch) (mismatches[r.provider] ??= []).add(r);
      if (r is ForeignChargeResolved) resolved++;
    }
    final checks = <Provider, int>{};
    for (final t in matched.where((t) => t.message.balance != null)) {
      checks[t.message.provider] = (checks[t.message.provider] ?? 0) + 1;
    }
    print('\nBALANCE CHECK (foreign charges resolved from the gap: $resolved)');
    for (final p in Provider.values) {
      final list = mismatches[p] ?? [];
      final gaps = list.map((m) => m.gap ~/ 100).toList()..sort();
      print('  ${p.name}: ${checks[p] ?? 0} messages with a balance, ${list.length} mismatches'
          '${gaps.isEmpty ? '' : ', smallest ${gaps.first}, largest ${gaps.last} RWF'}');
    }
    expect(rows, isNotEmpty);
  }, skip: export == null ? 'no sms-*.html export in the project root' : false);
}
