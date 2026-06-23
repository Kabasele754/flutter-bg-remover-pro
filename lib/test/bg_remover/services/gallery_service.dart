import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

class BgRemoverGalleryService {
  static Future<bool> saveToGallery(
    Uint8List bytes, {
    String name = 'bg_removed',
    String extension = 'png',
  }) async {
    if (await _requestPermission()) {
      try {
        final result = await SaverGallery.saveImage(
          bytes,
          fileName: '${name}_${DateTime.now().millisecondsSinceEpoch}.$extension',
          quality: 100,
          androidRelativePath: 'Pictures/BgRemoverPro',
          skipIfExists: false,
        );
        return result.isSuccess;
      } catch (e) {
        print('Save error: $e');
        return false;
      }
    }
    return false;
  }

  static Future<bool> shareImage(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    String? text,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [
            XFile.fromData(
              bytes,
              name: fileName,
              mimeType: mimeType,
            ),
          ],
        ),
      );
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed;
    } catch (e) {
      print('Share error: $e');
      return false;
    }
  }

  static Future<bool> _requestPermission() async {
    var photoStatus = await Permission.photos.status;
    if (photoStatus.isGranted) return true;

    var storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final photoResult = await Permission.photos.request();
    if (photoResult.isGranted) return true;

    final storageResult = await Permission.storage.request();
    return storageResult.isGranted;
  }
}
