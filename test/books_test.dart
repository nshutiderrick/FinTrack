import 'package:expense_tracker/core/ledger.dart';
import 'package:expense_tracker/core/loans.dart';
import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/notices.dart';
import 'package:expense_tracker/core/people.dart';
import 'package:expense_tracker/core/subscriptions.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 6, 1, 10);
var _n = 0;

ParsedMessage msg(
  Provider p,
  Kind kind,
  Direction dir,
  int rwf, {
  int days = 0,
  int minutes = 0,
  String? who,
  String? phone,
  bool person = false,
  String? loanId,
  String? note,
  String currency = 'RWF',
}) =>
    ParsedMessage(
      provider: p,
      kind: kind,
      direction: dir,
      time: t0.add(Duration(days: days, minutes: minutes)),
      amount: rwf * 100,
      counterparty: who,
      phone: phone,
      isPerson: person,
      loanId: loanId,
      note: note,
      currency: currency,
      reference: 'ref${_n++}',
    );

TxRecord rec(ParsedMessage m, {String? category, String? loanLink}) =>
    TxRecord(id: 'r${_n++}', source: TxSource.alert, message: m, category: category, loanLink: loanLink);

List<Tx> txs(List<TxRecord> r) => Ledger.build(r).txs;

final me = OwnIdentity(names: const ['Test Owner'], phones: const ['0780000001']);

void main() {
  group('Loans', () {
    test('an app loan: approval, money in, repayments by id, closure', () {
      final book = LoanBook.build(
        txs([
          rec(msg(Provider.mtn, Kind.loanInfo, Direction.none, 80000, who: 'MoFaya', loanId: '77', note: 'approved')),
          rec(msg(Provider.mtn, Kind.loanReceived, Direction.inflow, 80000, minutes: 1, who: 'MoFaya Loans')),
          rec(msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 50000, days: 10, who: 'MoFaya', loanId: '77')),
          rec(msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 37200, days: 20, who: 'MoFaya', loanId: '77')),
        ]),
        const [],
      );
      final loan = book.iOwe.single;
      expect(loan.borrowed, 8000000);
      expect(loan.source, isNotNull);
      expect(loan.repaid, 8720000);
      expect(loan.closed, isFalse); // interest unknown until the closure message
      expect(loan.left, isNull);

      final closed = LoanBook.build(
        txs([
          rec(msg(Provider.mtn, Kind.loanInfo, Direction.none, 80000, who: 'MoFaya', loanId: '77', note: 'approved')),
          rec(msg(Provider.mtn, Kind.loanInfo, Direction.none, 80000, days: 21, who: 'MoFaya', loanId: '77', note: 'closed')),
        ]),
        const [],
      );
      expect(closed.iOwe.single.closed, isTrue);
      expect(closed.open, isEmpty);
    });

    test('a repayment with no id goes to the open loan of the same lender', () {
      final book = LoanBook.build(
        txs([
          rec(msg(Provider.mtn, Kind.loanReceived, Direction.inflow, 20000, who: 'Mokash Loan Account')),
          rec(msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 5000, days: 3, who: 'Mokash Loan')),
          rec(msg(Provider.mtn, Kind.loanRepayment, Direction.outflow, 900, days: 4, who: 'Someone Else')),
        ]),
        const [],
      );
      expect(book.iOwe.single.repaid, 500000);
      expect(book.unlinked, hasLength(1));
    });

    test('I lent this: the send is the source, money back reduces what is owed', () {
      final lent = LoanRecord(
          id: 'L1', side: LoanSide.owedToMe, person: 'Friend A', amount: 1000000, createdAt: t0, due: t0.add(const Duration(days: 7)));
      final book = LoanBook.build(
        txs([
          rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 10000, who: 'Friend A', person: true), loanLink: 'L1'),
          rec(msg(Provider.mtn, Kind.income, Direction.inflow, 4000, days: 5, who: 'Friend A', person: true), loanLink: 'L1'),
        ]),
        [lent],
      );
      final loan = book.owedToMe.single;
      expect(loan.source, isNotNull);
      expect(loan.left, 600000);
      expect(book.totalLeft(LoanSide.owedToMe), 600000);
      expect(loan.overdue(t0.add(const Duration(days: 8))), isTrue);
    });

    test('a lent amount and its repayment are not spending or income', () {
      final l = Ledger.build([
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 10000, who: 'Friend A', person: true), loanLink: 'L1'),
      ]);
      expect(l.pending, isEmpty);
      expect(l.txs.single.confirmed, isFalse);
    });
  });

  group('Subscriptions', () {
    test('merchant key ignores case, dots and codes', () {
      expect(merchantKey('CLAUDE.AI SUBSCRIPTION'), 'CLAUDE');
      expect(merchantKey('Claude.ai subscr'), 'CLAUDE');
      expect(merchantKey('www.capcut.com'), 'CAPCUT');
    });

    test('a monthly card charge is suggested, then tracked once confirmed', () {
      final list = txs([
        for (var i = 0; i < 3; i++)
          rec(msg(Provider.equity, Kind.expense, Direction.outflow, 20, days: 30 * i, who: 'CLAUDE.AI SUBSCRIPTION', currency: 'USD')),
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 5000, days: 3, who: 'SIMBA SUPERMARKET')),
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 7000, days: 40, who: 'SIMBA SUPERMARKET')),
      ]);
      final book = SubscriptionBook.build(list, const []);
      expect(book.suggestions.map((s) => s.key), ['CLAUDE']);
      final s = book.suggestions.single;
      expect(s.cycle, Cycle.monthly);
      expect(s.payments, hasLength(3));
      expect(s.nextRenewal, DateTime(2026, 8, 31, 10)); // last charge 31 Jul

      final confirmed = SubscriptionBook.build(list, [
        SubRecord(id: 's1', name: 'Claude', key: 'CLAUDE', cycle: Cycle.monthly, status: SubStatus.active),
      ]);
      expect(confirmed.suggestions, isEmpty);
      expect(confirmed.active.single.payments, hasLength(3));
      expect(confirmed.costApproximate, isTrue); // USD with no RWF amount yet
    });

    test('monthly and yearly cost from known RWF amounts', () {
      final list = txs([
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 12000, who: 'CANAL PLUS')),
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 120000, days: 1, who: 'ANNUAL HOSTING')),
      ]);
      final book = SubscriptionBook.build(list, [
        SubRecord(id: 'a', name: 'Canal+', key: 'CANAL', cycle: Cycle.monthly, status: SubStatus.active),
        SubRecord(id: 'b', name: 'Hosting', key: 'ANNUAL', cycle: Cycle.yearly, status: SubStatus.active),
        SubRecord(id: 'c', name: 'Old', key: 'OLD', cycle: Cycle.monthly, status: SubStatus.cancelled),
      ]);
      expect(book.monthlyRwf, 1200000 + 1000000);
      expect(book.yearlyRwf, (1200000 + 1000000) * 12);
      expect(book.cancelled, hasLength(1));
    });

    test('a failed charge after the last payment is flagged, and a late renewal is missed', () {
      final list = txs([
        rec(msg(Provider.equity, Kind.expense, Direction.outflow, 3000, who: 'CAPCUT')),
        rec(msg(Provider.equity, Kind.failed, Direction.none, 3000, days: 30, who: 'CAPCUT')),
      ]);
      final s = SubscriptionBook.build(list, [
        SubRecord(id: 'x', name: 'CapCut', key: 'CAPCUT', cycle: Cycle.monthly, status: SubStatus.active),
      ]).active.single;
      expect(s.failedRecently, isTrue);
      expect(s.missed(t0.add(const Duration(days: 40))), isTrue);
      expect(s.missed(t0.add(const Duration(days: 20))), isFalse);
    });

    test('reminders: a day before, and a month before when more than a month was paid', () {
      SubRecord typed(DateTime from, DateTime until, {Cycle cycle = Cycle.monthly}) => SubRecord(
            id: 'p', name: 'Gym', key: '', cycle: cycle, status: SubStatus.active, firstRenewal: until, paidFrom: from);
      Subscription only(SubRecord r) => SubscriptionBook.build(const [], [r]).active.single;

      final three = only(typed(DateTime(2026, 9, 1), DateTime(2026, 12, 1)));
      expect(three.nextRenewal, DateTime(2026, 12, 1));
      expect(three.reminders, [DateTime(2026, 11, 1, 9), DateTime(2026, 11, 30, 9)]);

      final one = only(typed(DateTime(2026, 11, 1), DateTime(2026, 12, 1)));
      expect(one.reminders, [DateTime(2026, 11, 30, 9)]);

      // A month before 31 March is the last day of February.
      expect(only(typed(DateTime(2025, 12, 31), DateTime(2026, 3, 31))).reminders.first, DateTime(2026, 2, 28, 9));

      final cancelled = SubscriptionBook.build(const [], [
        SubRecord(id: 'c', name: 'Old', key: '', cycle: Cycle.monthly, status: SubStatus.cancelled, firstRenewal: DateTime(2026, 12, 1)),
      ]).cancelled.single;
      expect(cancelled.reminders, isEmpty);
    });

    test('a prepaid period is not cut short by a payment found in the messages', () {
      final list = txs([rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 30000, who: 'GYM CLUB'))]);
      final s = SubscriptionBook.build(list, [
        SubRecord(
            id: 'g', name: 'Gym club', key: 'GYM', cycle: Cycle.monthly, status: SubStatus.active,
            firstRenewal: DateTime(t0.year, t0.month + 3, t0.day), paidFrom: t0),
      ]).active.single;
      expect(s.nextRenewal, DateTime(t0.year, t0.month + 3, t0.day));
      expect(s.reminders, hasLength(2));
    });
  });

  group('Notices', () {
    test('a subscription running out soon and an overdue loan are listed, review first', () {
      final now = DateTime(2026, 11, 14, 12);
      final subs = SubscriptionBook.build(const [], [
        SubRecord(id: 's', name: 'Gym', key: '', cycle: Cycle.monthly, status: SubStatus.active, firstRenewal: DateTime(2026, 11, 15)),
        SubRecord(id: 'f', name: 'Far', key: '', cycle: Cycle.yearly, status: SubStatus.active, firstRenewal: DateTime(2027, 6, 1)),
      ]);
      final loans = LoanBook.build(const [], [
        LoanRecord(id: 'l', side: LoanSide.owedToMe, person: 'Friend One', amount: 500000, createdAt: DateTime(2026, 10, 1), due: DateTime(2026, 11, 10)),
      ]);
      final n = buildNotices(subs: subs, loans: loans, reviewCount: 2, now: now);
      expect(n.map((x) => x.title), ['Review', 'Friend One owes you', 'Gym']);
      expect(n.last.body, 'Runs out tomorrow.');
      expect(n[1].body, 'Was due 4 days ago.');
    });
  });

  group('People', () {
    test('groups by phone, joins masked numbers, leaves out my own accounts', () {
      final list = txs([
        rec(msg(Provider.mtn, Kind.expense, Direction.outflow, 1000, who: 'ALICE K', phone: '0788111222', person: true)),
        rec(msg(Provider.airtel, Kind.expense, Direction.outflow, 500, days: 1, who: 'Alice Kay', phone: '250788111222', person: true)),
        rec(msg(Provider.mtn, Kind.income, Direction.inflow, 2000, days: 2, who: 'ALICE K', phone: '07******222', person: true)),
        rec(msg(Provider.mtn, Kind.income, Direction.inflow, 9000, days: 3, who: 'Test Owner', phone: '0780000001', person: true)),
      ]);
      final people = People.build(list, me: me, nicknames: const {'788111222': 'Alice'});
      expect(people, hasLength(1));
      final alice = people.single;
      expect(alice.name, 'Alice');
      expect(alice.sent, 150000);
      expect(alice.received, 200000);
      expect(alice.txs, hasLength(3));
    });
  });
}
