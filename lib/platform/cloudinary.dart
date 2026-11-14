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

/// More than [CloudinaryUploader.maxBytes]; nothing was sent.
class PhotoTooLarge implements Exception {
  const PhotoTooLarge();
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

  /// The largest photo the app sends.
  static const maxBytes = 5 * 1024 * 1024;

  Future<UploadedPhoto> upload(Uint8List bytes, {String filename = 'photo.jpg'}) async {
    if (bytes.length > maxBytes) throw const PhotoTooLarge();
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

/// Camera or gallery, shrunk on the phone (longest side 1600 px) to well
/// under the 5 MB upload limit before upload.
Future<Uint8List?> pickExpensePhoto(ImageSource source) async {
  expectExternal();
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
  return file?.readAsBytes();
}
