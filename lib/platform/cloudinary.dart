import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../firebase_config.dart';
import 'leaving_app.dart';

class UploadedPhoto {
  const UploadedPhoto({required this.secureUrl, required this.publicId});
  final String secureUrl;
  final String publicId;
}

class CloudinaryException implements Exception {
  const CloudinaryException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'Cloudinary upload failed ($statusCode): $message';
}

/// Uploads expense photos with an unsigned preset (spec: "Photo Storage").
/// No API secret in the app; the preset decides folder, formats and size limit.
class CloudinaryUploader {
  CloudinaryUploader({http.Client? client, this.cloudName = cloudinaryCloudName, this.preset = cloudinaryUploadPreset})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String cloudName;
  final String preset;

  Future<UploadedPhoto> upload(Uint8List bytes, {String filename = 'photo.jpg'}) async {
    final request = http.MultipartRequest('POST', Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload'))
      ..fields['upload_preset'] = preset
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await _client.send(request));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = body['error'];
      throw CloudinaryException(
          response.statusCode, error is Map ? '${error['message']}' : response.body);
    }
    return UploadedPhoto(secureUrl: body['secure_url'] as String, publicId: body['public_id'] as String);
  }
}

/// Camera or gallery, shrunk on the phone to roughly 200 KB before upload.
Future<Uint8List?> pickExpensePhoto(ImageSource source) async {
  expectExternal();
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 70);
  return file?.readAsBytes();
}
