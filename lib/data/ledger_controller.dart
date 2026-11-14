import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/categories.dart' as defaults;
import '../core/ledger.dart';
import '../core/loans.dart';
import '../core/matcher.dart';
import '../core/models.dart';
import '../core/own_accounts.dart';
import '../core/parser.dart';
import '../core/people.dart';
import '../core/reconcile.dart';
import '../core/statement.dart';
import '../core/subscriptions.dart';
import '../platform/alerts.dart';
import '../platform/popup_settings.dart';
import '../popup/popup_logic.dart';
import '../security/app_lock.dart';
import 'ledger_store.dart';

/// What importing a statement did (spec: "Summary after import").
class ImportSummary {
  const ImportSummary({
    required this.rows,
    required this.known,
    required this.added,
    required this.transfersConfirmed,
    required this.foreignFilled,
    required this.mismatchesClosed,
    this.skippedBefore = 0,
    this.since,
    this.feesFixed = 0,
  });

  /// Transactions whose fee was completed from the statement.
  final int feesFixed;
  final int rows, known, added, transfersConfirmed, foreignFilled, mismatchesClosed;

  /// Rows dated before tracking started, left out.
  final int skippedBefore;
  final DateTime? since;
}

/// Keeps the [Ledger] up to date: reads the alerts the phone logged, parses
/// them with my identity, saves new ones, and rebuilds whenever a stored
/// transaction, loan, subscription or my profile changes.
class LedgerController extends ChangeNotifier {
  LedgerController(this.store, {this.alerts = const AlertsChannel(), this.popups = const PopupSettingsChannel()});

  final LedgerStore store;
  final AlertsChannel alerts;
  final PopupSettingsChannel popups;
  String? _sentPopupConfig;

  Ledger ledger = Ledger.empty;
  LoanBook loans = LoanBook.build(const [], const []);
  SubscriptionBook subscriptions = SubscriptionBook.build(const [], const []);
  List<Person> people = const [];
  bool loaded = false;
  bool listenerEnabled = true;

  List<String> ownNames = const [];
  List<String> ownPhones = const [];
  List<OwnAccount> ownAccounts = const [];

  /// My profile has been read at least once (so setup is not shown by mistake).
  bool profileLoaded = false;

  /// The day tracking started: the day the app was first installed. Kept in
  /// my profile, so a reinstall or a new phone keeps the original day.
  /// Statement rows before it are not imported.
  DateTime? trackingSince;
  bool _settingSince = false;

  Future<void> _ensureTrackingSince() async {
    if (trackingSince != null || _settingSince) return;
    _settingSince = true;
    final installed = await alerts.installedAt();
    _settingSince = false;
    if (installed == null || trackingSince != null) return;
    trackingSince = DateTime(installed.year, installed.month, installed.day);
    _write(store.saveProfile({'trackingSince': trackingSince!.millisecondsSinceEpoch}));
    notifyListeners();
  }

  String? _passcodeHash, _passcodeSalt;
  bool get hasPasscode => _passcodeHash != null && _passcodeSalt != null;
  bool checkPasscode(String pin) => hasPasscode && hashPasscode(pin, _passcodeSalt!) == _passcodeHash;

  /// Saves a new passcode (salted hash only) to my private profile.
  void setPasscode(String pin) {
    _passcodeSalt = newSalt();
    _passcodeHash = hashPasscode(pin, _passcodeSalt!);
    _write(store.saveProfile({'passcodeHash': _passcodeHash, 'passcodeSalt': _passcodeSalt}));
    notifyListeners();
  }

  /// After "Forgot passcode?" and a fresh Google sign-in: the lock then asks
  /// for a new one.
  void clearPasscode() {
    _passcodeHash = _passcodeSalt = null;
    _write(store.saveProfile({'passcodeHash': null, 'passcodeSalt': null}));
    notifyListeners();
  }

  /// The dashboard opens only once I have saved a name and an account.
  bool get setupDone => ownNames.isNotEmpty && ownAccounts.isNotEmpty;
  Map<Provider, int> starting = const {};
  Map<String, String> nicknames = const {};
  List<String>? _expenseCategories, _incomeCategories;

  List<String> get expenseCategories => _expenseCategories ?? defaults.expenseCategories;
  List<String> get incomeCategories => _incomeCategories ?? defaults.incomeCategories;
  OwnIdentity get me => OwnIdentity(names: ownNames, phones: ownPhones);

  /// Spellings of my name seen on both sides of a transfer and not saved yet,
  /// one per distinct name (word order and case ignored).
  List<String> get suggestedNames {
    final out = <String>[];
    for (final n in ledger.learnedNames) {
      if (me.isOwnName(n) || out.any((o) => OwnIdentity.sameName(o, n))) continue;
      out.add(n);
    }
    return out;
  }

  void addOwnName(String name) => saveProfile(names: [...ownNames, name]);

  Map<String, Doc> _docs = const {};
  Map<String, TxRecord> _records = const {};
  List<LoanRecord> _loanRecords = const [];
  List<SubRecord> _subRecords = const [];
  List<RawAlert> _raw = const [];

  /// Fresh parses of the alerts on this phone, by id. They win over the stored
  /// copy, so a better parser or a change to my names applies to old alerts too.
  Map<String, ParsedMessage> _parsed = const {};
  final List<StreamSubscription<Object?>> _subs = [];
  bool _gotDocs = false;

  static List<String>? _strings(Object? v) => v is List ? v.whereType<String>().toList() : null;

  void start() {
    _subs.add(store.watchProfile().listen((p) {
      ownNames = _strings(p['names']) ?? const [];
      ownAccounts = [for (final a in (p['accounts'] as List?) ?? const []) ?OwnAccount.fromMap(a)];
      ownPhones = ownAccounts.isEmpty ? (_strings(p['phones']) ?? const []) : [for (final a in ownAccounts) a.number];
      _passcodeHash = p['passcodeHash'] as String?;
      _passcodeSalt = p['passcodeSalt'] as String?;
      final since = p['trackingSince'];
      trackingSince = since is int ? DateTime.fromMillisecondsSinceEpoch(since) : trackingSince;
      profileLoaded = true;
      unawaited(_ensureTrackingSince());
      final s = (p['starting'] as Map?)?.cast<String, Object?>() ?? const {};
      starting = {
        for (final e in s.entries)
          if (e.value is int) Provider.values.byName(e.key): e.value as int,
      };
      final n = (p['nicknames'] as Map?)?.cast<String, Object?>() ?? const {};
      nicknames = {for (final e in n.entries) if (e.value is String) e.key: e.value as String};
      _expenseCategories = _strings(p['expenseCategories']);
      _incomeCategories = _strings(p['incomeCategories']);
      _reparse();
    }));
    _subs.add(store.watchTransactions().listen((docs) {
      _docs = docs;
      _gotDocs = true;
      _save();
      _rebuild();
    }));
    _subs.add(store.watch(LedgerStore.loans).listen((docs) {
      _loanRecords = [for (final e in docs.entries) ?_tryRead(() => LoanRecord.fromMap(e.key, e.value))];
      _rebuild();
    }));
    _subs.add(store.watch(LedgerStore.subscriptions).listen((docs) {
      _subRecords = [for (final e in docs.entries) ?_tryRead(() => SubRecord.fromMap(e.key, e.value))];
      _rebuild();
    }));
    _subs.add(alerts.alerts.listen((_) => refresh()));
    refresh();
  }

  static T? _tryRead<T>(T Function() f) {
    try {
      return f();
    } catch (e) {
      debugPrint('Skipping unreadable document: $e');
      return null;
    }
  }

  /// Reads the phone's alert log again (on open, on resume, on a new alert).
  Future<void> refresh() async {
    listenerEnabled = await alerts.isListenerEnabled();
    _raw = await alerts.allAlerts();
    for (final d in await popups.takeDecisions()) {
      _applyPopupDecision(d);
    }
    _reparse();
  }

  /// A choice made in the floating pop-up while the app was closed. The
  /// transaction's id is the alert's id, so it is saved straight onto it.
  void _applyPopupDecision(PopupDecision d) {
    final description = d.description == null ? null : {'description': d.description};
    if (d.transfer) {
      _write(store.merge(d.alertId, {'kindOverride': Kind.transfer.name, 'category': null, ...?description}));
    } else if (d.lent) {
      final loanId = store.addIn(
        LedgerStore.loans,
        LoanRecord(id: '', side: LoanSide.owedToMe, person: d.title, amount: d.amount, createdAt: d.time).toMap(),
      );
      _write(store.merge(d.alertId, {'loanLink': loanId, ...?description}));
    } else if (d.category != null) {
      _write(store.merge(d.alertId, {'category': d.category, ...?description}));
    }
  }

  /// What the pop-up needs to know, kept on the phone: who I am, my
  /// categories, and what I picked for each payee before (offered first).
  void _sendPopupConfig() {
    final lastByPayee = <String, String>{};
    final counts = {false: <String, int>{}, true: <String, int>{}};
    for (final t in ledger.txs) {
      if (!t.confirmed) continue;
      final payee = t.m.counterparty?.toUpperCase().trim();
      if (payee != null) lastByPayee.putIfAbsent(payee, () => t.category!); // newest first
      final c = counts[t.isIncome]!;
      c[t.category!] = (c[t.category!] ?? 0) + 1;
    }
    List<String> top(Map<String, int> m) => (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).take(4).toList();
    final config = PopupConfig(
      names: ownNames,
      phones: ownPhones,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
      lastCategoryByPayee: lastByPayee,
      topExpense: top(counts[false]!),
      topIncome: top(counts[true]!),
    );
    final json = config.toMap().toString();
    if (json == _sentPopupConfig) return;
    _sentPopupConfig = json;
    unawaited(popups.setConfig(config));
  }

  void _reparse() {
    final parser = MessageParser(me);
    final parsed = <String, ParsedMessage>{};
    for (final a in _raw) {
      final sender = a.sender;
      if (sender == null) continue;
      final m = parser.parse(sender, a.text, a.postedAt);
      if (m == null || m.kind == Kind.ignore) continue;
      parsed[a.id] = m;
    }
    _parsed = parsed;
    _save();
    _rebuild();
  }

  /// Writes alerts that are new or now parse differently. Parsed fields only;
  /// the decision fields on the document are left alone.
  void _save() {
    if (!_gotDocs) return; // wait for the stored copy, or everything looks new
    _parsed.forEach((id, m) {
      final fields = TxRecord(id: id, source: TxSource.alert, message: m).parsedMap();
      final doc = _docs[id];
      if (doc == null || fields.entries.any((e) => doc[e.key] != e.value)) _write(store.merge(id, fields));
    });
  }

  void _rebuild() {
    final records = <String, TxRecord>{};
    _docs.forEach((id, d) {
      final r = _tryRead(() => TxRecord.fromMap(id, d));
      if (r == null) return;
      final fresh = _parsed[id];
      records[id] = fresh == null ? r : r.withMessage(fresh);
    });
    _parsed.forEach((id, m) => records.putIfAbsent(id, () => TxRecord(id: id, source: TxSource.alert, message: m)));
    _records = records;
    ledger = Ledger.build(records.values, starting: starting);
    loans = LoanBook.build(ledger.txs, _loanRecords);
    subscriptions = SubscriptionBook.build(ledger.txs, _subRecords);
    people = People.build(ledger.txs, me: me, nicknames: nicknames);
    if (profileLoaded && _gotDocs) _sendPopupConfig();
    loaded = _gotDocs;
    notifyListeners();
  }

  // ------------------------------------------------------------- my decisions

  void setCategory(String id, String category, {String? description}) => _write(store.merge(id, {
        'category': category,
        if (description != null) 'description': description.trim().isEmpty ? null : description.trim(),
      }));

  void setDescription(String id, String description) =>
      _write(store.merge(id, {'description': description.trim().isEmpty ? null : description.trim()}));

  /// Says what a "Needs review" message really is. Clearing the category lets
  /// the normal flow ask for one again.
  void setKind(String id, Kind kind) => _write(store.merge(id, {'kindOverride': kind.name, 'category': null}));

  /// "Between my accounts" in the category picker: the app missed that this
  /// was my own money moving. With [remember], the other side's name and
  /// number are saved as mine, so the next one is caught on its own.
  void markAsTransfer(Tx tx, {bool remember = false}) {
    setKind(tx.id, Kind.transfer);
    if (!remember) return;
    final m = tx.m;
    final names = [...ownNames];
    final accounts = [...ownAccounts];
    final name = m.counterparty?.trim();
    if (name != null && name.isNotEmpty && !me.isOwnName(name)) names.add(name);
    final phone = m.phone?.replaceAll(RegExp(r'\D'), '');
    final type = phone == null ? null : accountTypeOfPhone(phone);
    if (phone != null && type != null && !me.isOwnPhone(phone)) accounts.add(OwnAccount(type, phone));
    if (names.length != ownNames.length || accounts.length != ownAccounts.length) {
      saveIdentity(names: names, accounts: accounts);
    }
  }

  void acceptMismatch(String id) => _write(store.merge(id, {'accepted': true}));

  /// "Accept all as is" on the Mismatches tab.
  void acceptMismatches(Iterable<String> ids) {
    for (final id in ids) {
      acceptMismatch(id);
    }
  }

  void setPhoto(String id, String url, String publicId) =>
      _write(store.merge(id, {'photoUrl': url, 'photoId': publicId}));

  /// Unlinks the photo. The file itself can be deleted from the Cloudinary
  /// dashboard (deleting by API needs the secret, which the app does not hold).
  void removePhoto(String id) => _write(store.merge(id, {'photoUrl': null, 'photoId': null}));

  /// A manual entry is saved with its category straight away (spec: Manual Entry).
  void addManual({
    required Provider account,
    required bool income,
    required int amount,
    required DateTime time,
    required String category,
    String? description,
    String? name,
    String? phone,
    int fee = 0,
    String? reference,
  }) {
    String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    // Amount and fee change the account's running balance like an alert would.
    final m = ParsedMessage(
      provider: account,
      kind: income ? Kind.income : Kind.expense,
      direction: income ? Direction.inflow : Direction.outflow,
      time: time,
      amount: amount,
      fee: fee,
      counterparty: clean(name),
      isPerson: clean(name) != null,
      phone: clean(phone),
      reference: clean(reference),
    );
    store.add({
      ...TxRecord(id: '', source: TxSource.manual, message: m).parsedMap(),
      'category': category,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    });
  }

  /// Only manual entries can be deleted: an alert would come back on the next read.
  void deleteManual(String id) => _write(store.delete(id));

  void saveProfile({List<String>? names, List<String>? phones}) {
    _write(store.saveProfile({'names': ?names, 'phones': ?phones}));
  }

  /// Saves my names and accounts together (setup and Settings). The numbers
  /// are also kept as a plain list, which is what transfer matching reads.
  void saveIdentity({required List<String> names, required List<OwnAccount> accounts}) {
    // Shown at once, so leaving setup does not wait for the cloud round trip.
    ownNames = names;
    ownAccounts = accounts;
    ownPhones = [for (final a in accounts) a.number];
    _write(store.saveProfile({
      'names': names,
      'accounts': [for (final a in accounts) a.toMap()],
      'phones': ownPhones,
    }));
    _reparse();
  }

  /// "Erase all data and start again": deletes everything in my account and
  /// the alerts logged on the phone, then starts over from today with setup.
  /// Permanent. Appearance and other phone settings are kept.
  Future<void> eraseAll() async {
    await store.deleteAll();
    await alerts.resetLocal();
    final today = DateTime.now();
    trackingSince = DateTime(today.year, today.month, today.day);
    ownNames = const [];
    ownPhones = const [];
    ownAccounts = const [];
    nicknames = const {};
    _passcodeHash = _passcodeSalt = null;
    _expenseCategories = null;
    _incomeCategories = null;
    _raw = const [];
    _parsed = const {};
    _docs = const {};
    _loanRecords = const [];
    _subRecords = const [];
    _sentPopupConfig = null;
    // Statements are read from today on after a fresh start.
    _write(store.saveProfile({'trackingSince': trackingSince!.millisecondsSinceEpoch}));
    _rebuild();
  }

  // ------------------------------------------------------------------ loans

  void addLoan({
    required LoanSide side,
    required String person,
    required int amount,
    required DateTime createdAt,
    int? totalToRepay,
    DateTime? due,
    String? note,
  }) {
    store.addIn(
      LedgerStore.loans,
      LoanRecord(
        id: '',
        side: side,
        person: person,
        amount: amount,
        totalToRepay: totalToRepay,
        createdAt: createdAt,
        due: due,
        note: note,
      ).toMap(),
    );
  }

  /// "I lent this": the payment becomes money owed to me, not spending.
  void lendFromTx(Tx tx, {DateTime? due, String? note}) {
    final id = store.addIn(
      LedgerStore.loans,
      LoanRecord(
        id: '',
        side: LoanSide.owedToMe,
        person: tx.title,
        amount: tx.rwf,
        createdAt: tx.time,
        due: due,
        note: note,
      ).toMap(),
    );
    linkToLoan(tx.id, id);
  }

  void linkToLoan(String txId, String loanId) => _write(store.merge(txId, {'loanLink': loanId}));
  void unlinkLoan(String txId) => _write(store.merge(txId, {'loanLink': null}));
  void closeLoan(String id) => _write(store.mergeIn(LedgerStore.loans, id, {'closed': true}));

  /// Deletes a loan I added; its payments go back to being normal transactions.
  void deleteLoan(Loan l) {
    for (final t in [?l.source, ...l.payments]) {
      unlinkLoan(t.id);
    }
    _write(store.deleteIn(LedgerStore.loans, l.id));
  }

  // ---------------------------------------------------------- subscriptions

  void trackSubscription(Subscription s) => store.addIn(
        LedgerStore.subscriptions,
        SubRecord(
          id: '',
          name: s.name,
          key: s.key,
          cycle: s.cycle,
          status: SubStatus.active,
          amount: s.rwf,
          currency: s.currency,
          account: s.last?.provider,
        ).toMap(),
      );

  /// "Not a subscription": stops suggesting this merchant.
  void dismissSubscription(Subscription s) => store.addIn(
        LedgerStore.subscriptions,
        SubRecord(id: '', name: s.name, key: s.key, cycle: s.cycle, status: SubStatus.dismissed).toMap(),
      );

  void addSubscription({
    required String name,
    required int amount,
    required Cycle cycle,
    required Provider account,
    required DateTime nextRenewal,
  }) =>
      store.addIn(
        LedgerStore.subscriptions,
        SubRecord(
          id: '',
          name: name,
          key: merchantKey(name),
          cycle: cycle,
          status: SubStatus.active,
          amount: amount,
          account: account,
          firstRenewal: nextRenewal,
        ).toMap(),
      );

  void setSubscriptionStatus(String id, SubStatus status) =>
      _write(store.mergeIn(LedgerStore.subscriptions, id, {'status': status.name}));

  void deleteSubscription(String id) => _write(store.deleteIn(LedgerStore.subscriptions, id));

  // ------------------------------------------------------- people, categories

  /// A nickname applies to every past and future transfer with that number.
  void setNickname(String personKey, String? nickname) => _write(store.saveProfile({
        'nicknames': {personKey: nickname},
      }));

  void setCategories({required bool income, required List<String> list}) =>
      _write(store.saveProfile({income ? 'incomeCategories' : 'expenseCategories': list}));

  /// Renames the category and every transaction that already has it.
  void renameCategory(String from, String to, {required bool income}) {
    final list = income ? incomeCategories : expenseCategories;
    setCategories(income: income, list: [for (final c in list) c == from ? to : c]);
    final dir = income ? Direction.inflow : Direction.outflow;
    for (final r in _records.values) {
      if (r.category == from && r.message.direction == dir) _write(store.merge(r.id, {'category': to}));
    }
  }

  // --------------------------------------------------------------- statements

  /// Reads statement text, adds what the alerts missed, confirms MoMo payments
  /// to Equity as transfers and fills in RWF amounts for foreign charges.
  /// Returns null when the text is not a supported statement.
  ImportSummary? importStatement(List<String> lines) {
    final all = StatementParser.parse(lines);
    if (all == null) return null;
    // Only what happened since the app was installed; earlier rows are ignored.
    final since = trackingSince;
    final rows = since == null ? all : rowsSince(all, since);
    final txOf = Map<Matched, Tx>.identity();
    for (final t in ledger.txs) {
      txOf[t.matched] = t;
    }
    final result = StatementReconciler(me).reconcile(rows, txOf.keys.toList());

    final records = Map.of(_records);
    var added = 0;
    for (final m in result.missing) {
      final id = 'st${fnv1a('${m.provider.name}|${m.time.millisecondsSinceEpoch}|${m.direction.name}|${m.amount}|${m.reference}|${m.balance}')}';
      if (records.containsKey(id)) continue;
      final r = TxRecord(id: id, source: TxSource.statement, message: m);
      records[id] = r;
      _write(store.merge(id, r.parsedMap()));
      added++;
    }
    for (final t in result.confirmedTransfers) {
      final tx = txOf[t];
      if (tx == null) continue;
      _write(store.merge(tx.id, {'kindOverride': Kind.transfer.name}));
      final r = records[tx.id];
      if (r != null) records[tx.id] = _override(r, kind: Kind.transfer);
    }
    var foreign = 0;
    for (final (t, amount) in result.foreignAmounts) {
      final tx = txOf[t];
      if (tx == null) continue;
      _write(store.merge(tx.id, {'rwfAmount': amount}));
      final r = records[tx.id];
      if (r != null) records[tx.id] = _override(r, rwfAmount: amount);
      foreign++;
    }

    // The statement's full fee (charges folded into their transaction) replaces a smaller alert fee.
    var feesFixed = 0;
    for (final (t, fee) in result.feeFixes) {
      final tx = txOf[t];
      if (tx == null) continue;
      _write(store.merge(tx.id, {'feeOverride': fee}));
      final r = records[tx.id];
      if (r != null) records[tx.id] = _override(r, feeOverride: fee);
      feesFixed++;
    }

    final before = ledger.openMismatches.length;
    final after = Ledger.build(records.values, starting: starting).openMismatches.length;
    return ImportSummary(
      rows: all.length,
      skippedBefore: all.length - rows.length,
      since: since,
      known: result.known.length,
      added: added,
      transfersConfirmed: result.confirmedTransfers.length,
      foreignFilled: foreign,
      feesFixed: feesFixed,
      mismatchesClosed: (before - after).clamp(0, before),
    );
  }

  static TxRecord _override(TxRecord r, {Kind? kind, int? rwfAmount, int? feeOverride}) => TxRecord(
        id: r.id,
        source: r.source,
        message: r.message,
        category: r.category,
        description: r.description,
        kindOverride: kind ?? r.kindOverride,
        accepted: r.accepted,
        loanLink: r.loanLink,
        photoUrl: r.photoUrl,
        photoId: r.photoId,
        rwfAmount: rwfAmount ?? r.rwfAmount,
        feeOverride: feeOverride ?? r.feeOverride,
      );

  void _write(Future<void> f) => unawaited(f.catchError((Object e) => debugPrint('Save failed: $e')));

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

class LedgerScope extends InheritedNotifier<LedgerController> {
  const LedgerScope({super.key, required LedgerController controller, required super.child})
      : super(notifier: controller);

  static LedgerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LedgerScope>()!.notifier!;

  static LedgerController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LedgerScope>()?.notifier;
}

/// Owns a [LedgerController] for the signed-in user and refreshes it whenever
/// the app comes back to the front.
class LedgerHost extends StatefulWidget {
  const LedgerHost({super.key, required this.store, required this.child, this.alerts = const AlertsChannel()});

  final LedgerStore store;
  final AlertsChannel alerts;
  final Widget child;

  @override
  State<LedgerHost> createState() => _LedgerHostState();
}

class _LedgerHostState extends State<LedgerHost> with WidgetsBindingObserver {
  late final LedgerController _c = LedgerController(widget.store, alerts: widget.alerts)..start();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LedgerScope(controller: _c, child: widget.child);
}
