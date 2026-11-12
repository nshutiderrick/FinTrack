import 'dart:convert';

import 'package:http/http.dart' as http;

import '../firebase_config.dart';

class EmailException implements Exception {
  const EmailException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'Email failed ($statusCode): $message';
}

/// Emails the "Forgot passcode" code through EmailJS's REST API. The EmailJS
/// account must allow API calls from non-browser apps (Account → Security).
class ResetCodeMailer {
  ResetCodeMailer({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<void> send({required String email, required String code}) async {
    final response = await _client.post(
      Uri.https('api.emailjs.com', '/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': emailJsServiceId,
        'template_id': emailJsTemplateId,
        'user_id': emailJsPublicKey,
        'template_params': {'to_email': email, 'code': code, 'app_name': 'FinTrack'},
      }),
    );
    if (response.statusCode != 200) throw EmailException(response.statusCode, response.body);
  }
}
