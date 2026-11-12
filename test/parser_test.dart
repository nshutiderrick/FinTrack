import 'package:expense_tracker/core/models.dart';
import 'package:expense_tracker/core/parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Formats copied from real alerts; names, numbers and ids are made up.
final me = OwnIdentity(names: ['Jean Mugabo'], phones: ['250788000111', '250733000222']);
final parser = MessageParser(me);
final rx = DateTime(2026, 11, 11, 9);

ParsedMessage p(String sender, String body) => parser.parse(sender, body, rx)!;

void main() {
  test('an Airtel payment to E Kash is a transfer to my Equity wallet', () {
    final m = MessageParser(OwnIdentity(names: const [], phones: const []))
        .parse('AirtelMoney', '*164*TXN ID (MP261112.1234.Q12345)*S*Kwishyura RWF5000 kuri E Kash App Kode 123456 byagenze neza.Ubu mufite RWF100. *KR#', DateTime(2026, 11, 12))!;
    expect(m.kind, Kind.transfer);
    expect(m.amount, 500000);
    expect(m.counterparty, 'eKash');
  });

  test('unknown sender is skipped', () {
    expect(parser.parse('Safaricom', 'hello', rx), isNull);
  });

  group('MTN', () {
    test('merchant payment strips the code and keeps the balance', () {
      final m = p('M-Money',
          'TxId:31845225745*S*Your payment of 3,600 RWF to SAWA CITI LTD. 919324 was completed at 2026-11-10 17:21:33.  Balance: 8,793 RWF. Fee 0 RWF.*EN#');
      expect(m.kind, Kind.expense);
      expect(m.amount, 360000);
      expect(m.counterparty, 'SAWA CITI LTD');
      expect(m.balance, 879300);
      expect(m.reference, '31845225745');
      expect(m.time, DateTime(2026, 11, 10, 17, 21, 33));
    });

    test('send to a person, all three fee wordings', () {
      for (final body in [
        '*165*S*500 RWF transferred to Alice MUKAMANA (250783000001) at 2026-11-10 19:55:30 .Fee: 20RWF.Balance: 7653RWF.Dial *182*1*3# and send money abroad *EN#',
        '*165*S*500 RWF transferred to Alice MUKAMANA (250783000001) at 2026-03-10 19:55:30 .Fee : 20 RWF. Balance: 7653 RWF. *EN#',
        '*165*S*500 RWF transferred to Alice MUKAMANA (250783000001) from 26641098 at 2025-09-29 17:46:27 .Fee was: 20 RWF. New balance: 7653 RWF. To Buy Airtime *EN#',
      ]) {
        final m = p('M-Money', body);
        expect(m.kind, Kind.expense, reason: body);
        expect(m.isPerson, isTrue);
        expect(m.phone, '250783000001');
        expect(m.fee, 2000);
        expect(m.balance, 765300);
        expect(m.balanceDelta, -52000);
      }
    });

    test('send to my own number is a transfer', () {
      final m = p('M-Money',
          '*165*S*1000 RWF transferred to Jean MUGABO (250733000222) at 2026-11-06 13:54:40 .Fee: 20RWF.Balance: 3RWF. *EN#');
      expect(m.kind, Kind.transfer);
    });

    test('received from a person', () {
      final m = p('M-Money',
          'You have received 7600 RWF from Alice MUKAMANA (*********950) at 2026-11-08 11:58:10 . Balance:8483 RWF. FT Id: 31793203963.');
      expect(m.kind, Kind.income);
      expect(m.direction, Direction.inflow);
      expect(m.phone, '950');
      expect(m.balance, 848300);
    });

    test('received from my Equity account is a transfer', () {
      final m = p('M-Money',
          'You have received 1000 RWF from MUGABO  JEAN MUGABO  JEAN (*********572) at 2026-10-20 13:42:30. Message from sender: Transfer from MUGABO JEAN-250788000111 Equity B2C. Balance:2363 RWF. FT Id: 31358514307.');
      expect(m.kind, Kind.transfer);
    });

    test('money from abroad names the real sender', () {
      final m = p('M-Money',
          'You have received 10210 RWF from THUNES LTD (*********125) at 2026-11-10 13:12:46. Message from sender: GRACE UWASE. Balance:12393 RWF. FT Id: 31840220887.');
      expect(m.kind, Kind.income);
      expect(m.counterparty, 'GRACE UWASE');
    });

    test('token payment: to me is a transfer, to someone else an expense, no name needs review', () {
      String body(String to) =>
          'TransactionId: 31713724312 Your payment of 4000 RWF to $to with token and ET Id:  SUCCESSFUL at 2026-11-04T20:53:45.902+02:00.Fee:20 RWF. Balance 2543 RWF.';
      expect(p('M-Money', body('JEAN MUGABO at EQUITY BANK')).kind, Kind.transfer);
      final other = p('M-Money', body('ERIC NKURUNZIZA at EQUITY BANK'));
      expect(other.kind, Kind.expense);
      expect(other.counterparty, 'ERIC NKURUNZIZA');
      expect(other.fee, 2000);
      expect(other.balance, 254300);
      expect(p('M-Money', body('EQUITY BANK RWANDA')).kind, Kind.needsReview);
    });

    test('savings, airtime and bundles', () {
      expect(
          p('M-Money',
                  '*162*TxId:29903247958*S*Your payment of 20000 RWF to Mokash Savings with token  and ET Id: 20260816000000008873154769 was completed at 2026-08-16 10:41:07. Fee 0 RWF. Balance: 10083 RWF .')
              .kind,
          Kind.savings);
      expect(
          p('M-Money',
                  '*162*TxId:29903247000*S*Your payment of 500 RWF to Airtime with token  and ET Id: 1 was completed at 2026-08-16 10:41:07. Fee 0 RWF. Balance: 9583 RWF .')
              .categoryHint,
          'Airtime');
      final data = p('M-Money',
          "*164*S*Y'ello, A transaction of 500 RWF by Data Bundle MTN was completed at 2026-11-04 13:00:00. Balance:4663 RWF. Fee  0 RWF. FT Id: 31700695461. ET  Id: 17937899712725828.*EN#");
      expect(data.kind, Kind.expense);
      expect(data.categoryHint, 'Data and voice bundles');
    });

    test('loan flow', () {
      expect(
          p('M-Money',
                  'Your loan application of 80000 RWF with id 2279123 created 2026-10-05 10:48:16 for MoFaya Loans has been successfully completed and approved.')
              .kind,
          Kind.loanInfo);
      final got = p('M-Money',
          'You have received 80000 RWF from MoFaya Loans  (*********890) on your mobile money account at 2026-10-05 10:48:36. Message from sender: . Your new balance:80789 RWF. Financial Transaction Id: 31020516173.');
      expect(got.kind, Kind.loanReceived);
      expect(got.balance, 8078900);
      final repay = p('M-Money',
          'Your repayment of 87200 RWF for loan id 2279123 to MoFaya has been successfully completed 2026-10-30 11:08:34. Loan transaction id: 18150329. Financial transaction id: 31580477869. External transaction id: 1.');
      final used = p('M-Money',
          '87200 RWF has been used to pay your loan at 2026-10-30 11:08:33. Your new balance: 17523 RWF. Financial Transaction Id: 31580477869.');
      expect([repay.kind, used.kind], [Kind.loanRepayment, Kind.loanRepayment]);
      expect(repay.reference, used.reference, reason: 'same id, so the duplicate check keeps one');
      expect(p('M-Money', 'Your loan BPR-LOANS-80000 with id 2279123 of 80000 RWF has been closed.').note, 'closed');
      final moflex = p('M-Money', 'Your loan YABX-LOANS-30 days-25000 with id 604197 of 25000 RWF has been closed.');
      expect(moflex.loanId, '604197');
      expect(moflex.counterparty, 'YABX-LOANS-30 days-25000');
    });

    test('failed and OTP messages', () {
      expect(
          p('M-Money',
                  "*143*R*Y'ello, the transaction with amount 500 RWF for Data Bundle MTN with message:  failed at 2026-08-30 22:11:20 .")
              .kind,
          Kind.failed);
      expect(p('M-Money', 'Y, your MoMo application one-time password is : 1234.').kind, Kind.ignore);
    });

    test('agent withdrawal adds the fee', () {
      final m = p('M-Money',
          'You have via agent: KAMANZI PAUL KAMANZI PAUL (*********792), withdrawn 5000 RWF at 2026-01-26 16:54:15 Balance: 732 RWF. Fee: 250 RWF. FT Id: 25679330410.');
      expect(m.kind, Kind.expense);
      expect(m.fee, 25000);
      expect(m.balance, 73200);
    });

    test('anything else needs review', () {
      expect(p('M-Money', 'Something new happened to 500 RWF').kind, Kind.needsReview);
    });
  });

  group('Equity', () {
    test('card charge in USD keeps the currency and arrival time', () {
      final m = p('EQUITYBANK',
          'Dear JEAN, Auth for card 5198..0000 Date:2026-11-05 02:06:12 Amt: USD 20.00 Details:ANTHROPIC* CLAUDE SUB . Customer Care: +250788190000/ +25073736000');
      expect(m.kind, Kind.expense);
      expect(m.currency, 'USD');
      expect(m.rwfKnown, isFalse);
      expect(m.amount, 2000);
      expect(m.counterparty, 'ANTHROPIC* CLAUDE SUB');
      expect(m.time, rx);
    });

    test('card amount with a space as thousands separator', () {
      final m = p('EQUITYBANK',
          'Dear JEAN, Auth for card 5198..0000 Date:2026-11-03 18:02:04 Amt: RWF 2 000.00 Details:SAWA CITI LTD . Customer Care: +250788190000');
      expect(m.kind, Kind.expense);
      expect(m.amount, 200000);
      expect(m.counterparty, 'SAWA CITI LTD');
    });

    test('newer received wording', () {
      final m = p('EQUITYBANK',
          'You have received 2000.00 RWF from ERIC  NKURUNZIZA 4********2655 to your Equity account 4********7957. Ref. W123 on 01/08/2026');
      expect(m.kind, Kind.income);
      expect(m.counterparty, 'ERIC NKURUNZIZA');
      expect(m.amount, 200000);
    });

    test('auth reversal cancels', () {
      expect(
          p('EQUITYBANK',
                  'Dear JEAN, Auth Reversal for card 5198..0000 Date:2026-08-13 06:26:07 Amt: EUR 0.93 Details:ORACLE IRELAND . Customer Care: +250788190000')
              .kind,
          Kind.cancel);
    });

    test('send with charges, SMS fee, balance and date', () {
      final m = p('EQUITYBANK',
          '3000.00 RWF has been successfully sent to Alice MUKAMANA 0*****9975 . Ref. A3OWDBARLUFN on 07/11/2026 at 12:49 CAT. Balance: RWF 1540.00 Charges  RWF 20.00, SMS alert charge RWF 4.00 Customer care: +250788190000');
      expect(m.kind, Kind.expense);
      expect(m.counterparty, 'Alice MUKAMANA');
      expect(m.fee, 2400);
      expect(m.balance, 154000);
      expect(m.reference, 'A3OWDBARLUFN');
      expect(m.time, DateTime(2026, 11, 7, 12, 49));
    });

    test('send to my own MTN number is a transfer, even with a stray brace', () {
      final m = p('EQUITYBANK',
          '1000.00 RWF was successfully sent to  250788000111. MTN Ref. AA0763E7EB4D0. Ref. AA0763E7EB4D0 on 20/10/26 at 13:42:21 CAT. Balance: } 1546.00 Charges  RWF 0.00 , SMS alert charge RWF} 4.00  Customer care: +250788190000');
      expect(m.kind, Kind.transfer);
      expect(m.balance, 154600);
      expect(m.fee, 400);
      expect(m.time, DateTime(2026, 10, 20, 13, 42));
    });

    test('older send wording without a balance', () {
      final m = p('EQUITYBANK',
          '500.00 RWF has been successfully sent to Bob KAYITARE 0*****9753 . Ref. 787065708458 on 18 Aug 2026 at 17:08 CAT. Charges 20.00 RWF');
      expect(m.kind, Kind.expense);
      expect(m.balance, isNull);
      expect(m.fee, 2000);
      expect(m.time, DateTime(2026, 8, 18, 17, 8));
    });

    test('received on eKash', () {
      final m = p('EQUITYBANK',
          'You have just received RWF 4000.00 4002000000000, REF  S2939343 04 Nov 2026 on eKash. Your new balance is RWF 37002.00');
      expect(m.kind, Kind.income);
      expect(m.amount, 400000);
      expect(m.balance, 3700200);
      expect(m.reference, 'S2939343');
      final own = p('EQUITYBANK',
          'You have received RWF 116000 ON 4**957 via incoming transfer  from MUGABO  JEAN On:  30-Oct-26 10:59:22 Balance RWF 117046 SMS RWF 0 Ref:50109869 Customer care: +250788190000');
      expect(own.kind, Kind.transfer);
      expect(own.balance, 11704600);
    });

    test('failed card charge is kept for subscriptions', () {
      final m = p('EQUITYBANK',
          'Dear Customer, your card no. 5198..0000 transaction to merchant CapCut for USD 8.59 has failed due to insufficient funds in your account.');
      expect(m.kind, Kind.failed);
      expect(m.counterparty, 'CapCut');
    });

    test('reversals, Kinyarwanda copies and notices', () {
      expect(
          p('EQUITYBANK',
                  "Sorry, your transaction couldn't be completed. We issued a reversal of 70000.00 RWF to account 4********7957 on 24/09/26 at 14:32:24 CAT. Ref. A7BCF3EDF1B3B")
              .kind,
          Kind.cancel);
      expect(p('EQUITYBANK', 'Munyamuryango, igikorwa cyo kwishyura ...').kind, Kind.ignore);
      expect(p('EQUITYBANK', 'Dear Member, eKash will be unavailable today. RWF 20 per transaction.').kind, Kind.ignore);
      expect(p('EQUITYBANK', 'Confirmed. Request to send RWF 3000 to ... has been received').kind, Kind.ignore);
    });
  });

  group('Airtel', () {
    test('airtime with balance and time from the id', () {
      final m = p('AirtelMoney',
          '*149*TID:RC261107.1608.E04012*S* Kugura Inite ya Rwf 5000 Byemeye kuri 733000222.Ubu kuri konti mufite Rwf 80 *KR#');
      expect(m.kind, Kind.expense);
      expect(m.categoryHint, 'Airtime');
      expect(m.balance, 8000);
      expect(m.time, DateTime(2026, 11, 7, 16, 8));
    });

    test('bundle, send and transfer in', () {
      expect(
          p('AirtelMoney',
                  '*150* TXN ID MP261004.1833.A03478*S*Ubu kuri konti yanyu mufite Rwf 0. Kugura Pack ya Rwf 4000 byagenze neza. *KR#')
              .categoryHint,
          'Data and voice bundles');
      final send = p('AirtelMoney',
          '*165* TID MP261107.1432.D04933*S* Usigaranye Rwf . Kohereza Rwf 190,000 kuri Irène KAYITESI 0786000003 muri MTN Byakunze. IGICIRO cya serivisi Rwf 20. *KR#');
      expect(send.kind, Kind.expense);
      expect(send.counterparty, 'Irène KAYITESI');
      expect(send.amount, 19000000);
      expect(send.fee, 2000);
      expect(send.balance, isNull);
      final inn = p('AirtelMoney',
          '*151*Txn ID CI261107.1605.B01790*R* You have received RWF 100 from Jean MUGABO 250788000111 in MTN Rwanda.Your NEW BALANCE isRWF 5080. *EN#');
      expect(inn.kind, Kind.transfer);
      expect(inn.balance, 508000);
      expect(inn.reference, 'CI261107.1605.B01790');
    });

    test('failures and wrong PIN', () {
      expect(p('AirtelMoney', 'Ibyo mwasabye ntibyakunze. Ntago mwemerewe').kind, Kind.failed);
      expect(p('AirtelMoney', 'PIN washyizemo siyo.').kind, Kind.ignore);
    });
  });

  group('OwnIdentity', () {
    test('names ignore order, case, spacing and repetition', () {
      expect(me.isOwnName('MUGABO  JEAN MUGABO JEAN'), isTrue);
      expect(me.isOwnName('Jean Mugabo Paul'), isFalse);
    });
    test('masked numbers need at least 4 visible digits', () {
      expect(me.isOwnPhone('0*****0111'), isTrue);
      expect(me.isOwnPhone('*********111'), isFalse);
    });
  });
}
