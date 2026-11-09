import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos werden mit der Kamera-App des Handys aufgenommen und im
/// geschuetzten Speicher der App abgelegt (fuer andere Apps nicht lesbar).
class PhotoService {
  static Future<String?> takePhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (x == null) return null;

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File(
      '${dir.path}/foto_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(x.path).copy(dest.path);
    return dest.path;
  }

  static Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
