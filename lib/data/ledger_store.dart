import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef Doc = Map<String, Object?>;

/// Where my data is kept: Firestore in the app, memory in tests.
/// Collections live under users/{uid}/: transactions, loans, subscriptions;
/// my names, nicknames and categories are in profile/main.
abstract class LedgerStore {
  static const transactions = 'transactions', loans = 'loans', subscriptions = 'subscriptions';

  /// Every document in [collection], id to fields, each time anything changes.
  Stream<Map<String, Doc>> watch(String collection);

  Stream<Doc> watchProfile();

  /// Merges [fields] into the document, creating it if needed.
  Future<void> mergeIn(String collection, String id, Doc fields);

  /// A new document with a generated id; returns the id.
  String addIn(String collection, Doc fields);

  Future<void> deleteIn(String collection, String id);

  Future<void> saveProfile(Doc fields);

  /// Deletes every transaction, loan, subscription and my profile. Permanent.
  Future<void> deleteAll();

  // Transactions are used the most.
  Stream<Map<String, Doc>> watchTransactions() => watch(transactions);
  Future<void> merge(String id, Doc fields) => mergeIn(transactions, id, fields);
  String add(Doc fields) => addIn(transactions, fields);
  Future<void> delete(String id) => deleteIn(transactions, id);
}

/// Firestore keeps a cache on the phone, so reads and writes work offline and
/// sync later. Writes are not awaited by callers: offline, they only finish
/// once the phone is back online.
class FirestoreLedgerStore extends LedgerStore {
  FirestoreLedgerStore(String uid, {FirebaseFirestore? db})
      : _user = (db ?? FirebaseFirestore.instance).collection('users').doc(uid);

  final DocumentReference<Doc> _user;

  DocumentReference<Doc> get _profile => _user.collection('profile').doc('main');

  @override
  Stream<Map<String, Doc>> watch(String collection) =>
      _user.collection(collection).snapshots().map((s) => {for (final d in s.docs) d.id: d.data()});

  @override
  Stream<Doc> watchProfile() => _profile.snapshots().map((s) => s.data() ?? const {});

  @override
  Future<void> mergeIn(String collection, String id, Doc fields) =>
      _user.collection(collection).doc(id).set(fields, SetOptions(merge: true));

  @override
  String addIn(String collection, Doc fields) {
    final ref = _user.collection(collection).doc();
    unawaited(ref.set(fields));
    return ref.id;
  }

  @override
  Future<void> deleteIn(String collection, String id) => _user.collection(collection).doc(id).delete();

  @override
  Future<void> saveProfile(Doc fields) => _profile.set(fields, SetOptions(merge: true));

  /// Firestore has no "delete collection" for apps, so documents go in
  /// batches of up to 400. Offline, the deletes wait and finish when online.
  @override
  Future<void> deleteAll() async {
    final refs = <DocumentReference<Doc>>[_profile];
    for (final c in [LedgerStore.transactions, LedgerStore.loans, LedgerStore.subscriptions]) {
      final snap = await _user.collection(c).get();
      refs.addAll(snap.docs.map((d) => d.reference));
    }
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _user.firestore.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      unawaited(batch.commit());
    }
  }
}

/// For tests and for running without Firebase.
class MemoryLedgerStore extends LedgerStore {
  final Map<String, Map<String, Doc>> collections = {};
  Doc profile = {};
  final Map<String, StreamController<Map<String, Doc>>> _streams = {};
  final _prof = StreamController<Doc>.broadcast();
  var _next = 0;

  Map<String, Doc> docsOf(String collection) => collections.putIfAbsent(collection, () => {});
  Map<String, Doc> get docs => docsOf(LedgerStore.transactions);

  Map<String, Doc> _copy(String c) => {for (final e in docsOf(c).entries) e.key: Map.of(e.value)};
  StreamController<Map<String, Doc>> _ctl(String c) =>
      _streams.putIfAbsent(c, () => StreamController<Map<String, Doc>>.broadcast());
  void _emit(String c) => scheduleMicrotask(() => _ctl(c).add(_copy(c)));

  @override
  Stream<Map<String, Doc>> watch(String collection) async* {
    yield _copy(collection);
    yield* _ctl(collection).stream;
  }

  @override
  Stream<Doc> watchProfile() async* {
    yield Map.of(profile);
    yield* _prof.stream;
  }

  @override
  Future<void> mergeIn(String collection, String id, Doc fields) async {
    final d = docsOf(collection);
    d[id] = {...?d[id], ...fields};
    _emit(collection);
  }

  @override
  String addIn(String collection, Doc fields) {
    final id = 'm${_next++}';
    docsOf(collection)[id] = Map.of(fields);
    _emit(collection);
    return id;
  }

  @override
  Future<void> deleteIn(String collection, String id) async {
    docsOf(collection).remove(id);
    _emit(collection);
  }

  @override
  Future<void> saveProfile(Doc fields) async {
    profile = {...profile, ...fields};
    scheduleMicrotask(() => _prof.add(Map.of(profile)));
  }

  @override
  Future<void> deleteAll() async {
    for (final c in collections.keys.toList()) {
      collections[c]!.clear();
      _emit(c);
    }
    profile = {};
    scheduleMicrotask(() => _prof.add(const {}));
  }
}
