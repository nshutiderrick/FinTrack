import 'ledger.dart';
import 'models.dart';

/// Someone I sent money to or received money from (spec: People Tracking).
class Person {
  Person(this.key, this.messageName, this.phone);

  /// The phone number's last 9 digits, or "name:..." when no number is known.
  final String key;
  String messageName;
  final String? phone;
  String? nickname;

  /// Newest first.
  final List<Tx> txs = [];

  String get name => nickname ?? messageName;
  int get sent => txs.where((t) => t.m.direction == Direction.outflow).fold(0, (s, t) => s + t.rwf);
  int get received => txs.where((t) => t.m.direction == Direction.inflow).fold(0, (s, t) => s + t.rwf);
  DateTime get last => txs.first.time;
}

class People {
  /// Phone numbers compare on their last 9 digits ("0788..." equals "250788...").
  static String? phoneKey(String? phone) {
    final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length < 9) return null;
    return d.substring(d.length - 9);
  }

  /// Groups person transfers by phone number. A masked number ("07*****726")
  /// joins the contact whose number ends in the same visible digits, if exactly
  /// one does. My own names and numbers are never listed.
  static List<Person> build(List<Tx> txs, {required OwnIdentity me, Map<String, String> nicknames = const {}}) {
    final byKey = <String, Person>{};
    final masked = <Tx>[];
    for (final t in txs) {
      final m = t.m;
      if (!m.isPerson || t.cancelled || t.kind == Kind.transfer) continue;
      if (me.isOwn(name: m.counterparty, phone: m.phone)) continue;
      final key = phoneKey(m.phone);
      if (key == null && (m.phone?.contains('*') ?? false)) {
        masked.add(t);
        continue;
      }
      final k = key ?? 'name:${(m.counterparty ?? '?').toUpperCase().trim()}';
      final p = byKey.putIfAbsent(k, () => Person(k, m.counterparty ?? 'Unknown', key == null ? null : m.phone));
      p.txs.add(t);
    }
    for (final t in masked) {
      final visible = RegExp(r'(\d+)$').firstMatch(t.m.phone!)?[1] ?? '';
      final hits = visible.length < 3 ? const <Person>[] : byKey.values.where((p) => p.phone != null && p.key.endsWith(visible)).toList();
      final Person p;
      if (hits.length == 1) {
        p = hits.single;
      } else {
        final k = 'name:${(t.m.counterparty ?? '?').toUpperCase().trim()}';
        p = byKey.putIfAbsent(k, () => Person(k, t.m.counterparty ?? 'Unknown', null));
      }
      p.txs.add(t);
    }
    for (final p in byKey.values) {
      p.txs.sort((a, b) => b.time.compareTo(a.time));
      p.messageName = p.txs.first.m.counterparty ?? p.messageName;
      p.nickname = nicknames[p.key];
    }
    return byKey.values.toList()..sort((a, b) => b.last.compareTo(a.last));
  }
}
