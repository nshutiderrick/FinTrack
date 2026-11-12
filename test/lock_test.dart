import 'dart:convert';

import 'package:expense_tracker/data/ledger_controller.dart';
import 'package:expense_tracker/firebase_config.dart';
import 'package:expense_tracker/platform/emailjs.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:expense_tracker/data/ledger_store.dart';
import 'package:expense_tracker/security/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the reset code is emailed through EmailJS to my address', () async {
    late Map<String, dynamic> sent;
    final mailer = ResetCodeMailer(client: MockClient((req) async {
      expect(req.url.toString(), 'https://api.emailjs.com/api/v1.0/email/send');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('OK', 200);
    }));
    await mailer.send(email: 'test.owner@example.com', code: '482913');
    expect(sent['service_id'], emailJsServiceId);
    expect(sent['template_params'], {'to_email': 'test.owner@example.com', 'code': '482913', 'app_name': 'FinTrack'});

    final refused = ResetCodeMailer(client: MockClient((_) async => http.Response('API calls are disabled', 403)));
    expect(refused.send(email: 'a@b.c', code: '1'), throwsA(isA<EmailException>()));
  });

  test('the passcode is stored only as a salted hash', () {
    final salt = newSalt();
    expect(hashPasscode('1234', salt), hashPasscode('1234', salt));
    expect(hashPasscode('1234', salt), isNot(hashPasscode('1235', salt)));
    expect(hashPasscode('1234', salt), isNot(hashPasscode('1234', newSalt())));
    expect(hashPasscode('1234', salt), isNot(contains('1234')));
  });

  test('set, check, change and clear the passcode', () async {
    final store = MemoryLedgerStore();
    final c = LedgerController(store);
    expect(c.hasPasscode, isFalse);
    c.setPasscode('2580');
    expect(c.checkPasscode('2580'), isTrue);
    expect(c.checkPasscode('0000'), isFalse);
    expect(store.profile['passcodeHash'], isA<String>());
    expect(store.profile.values, isNot(contains('2580')));
    c.setPasscode('1111');
    expect(c.checkPasscode('2580'), isFalse);
    expect(c.checkPasscode('1111'), isTrue);
    c.clearPasscode(); // after "Forgot passcode?" and signing in again
    expect(c.hasPasscode, isFalse);
  });
}
