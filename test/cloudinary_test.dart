import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/platform/cloudinary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uploads with the unsigned preset and returns url and id', () async {
    late http.BaseRequest sent;
    late String sentBody;
    final client = MockClient((req) async {
      sent = req;
      sentBody = req.body;
      return http.Response(jsonEncode({'secure_url': 'https://res.cloudinary.com/x/receipt.jpg', 'public_id': 'abc'}), 200);
    });
    final photo = await CloudinaryUploader(client: client, cloudName: 'demo', preset: 'p1')
        .upload(Uint8List.fromList([1, 2, 3]), filename: 'r.jpg');

    expect(sent.url.toString(), 'https://api.cloudinary.com/v1_1/demo/image/upload');
    expect(sentBody, contains('name="upload_preset"'));
    expect(sentBody, contains('p1'));
    expect(sentBody, isNot(contains('api_secret')));
    expect(photo.secureUrl, 'https://res.cloudinary.com/x/receipt.jpg');
    expect(photo.publicId, 'abc');
  });

  test('a rejected upload reports Cloudinary\'s message', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'error': {'message': 'Upload preset must be whitelisted for unsigned uploads'}}), 400));
    expect(
      CloudinaryUploader(client: client).upload(Uint8List(1)),
      throwsA(isA<CloudinaryException>().having((e) => e.message, 'message', contains('whitelisted'))),
    );
  });
}
