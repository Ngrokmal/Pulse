import 'dart:io';
import 'package:image_picker/image_picker.dart';

class PickedAttachment {
  final File file;
  final String fileName;
  final int fileSizeBytes;
  final String? mimeType;

  const PickedAttachment({
    required this.file,
    required this.fileName,
    required this.fileSizeBytes,
    this.mimeType,
  });
}

class ChatAttachmentPicker {
  ChatAttachmentPicker._();

  static final ImagePicker _picker = ImagePicker();

  static Future<PickedAttachment?> pickImage({required bool fromCamera}) async {
    final XFile? picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    return _toAttachment(picked);
  }

  static Future<PickedAttachment?> pickVideo({required bool fromCamera}) async {
    final XFile? picked = await _picker.pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    return _toAttachment(picked);
  }

  static Future<PickedAttachment?> pickGenericFile() async {
    final XFile? picked = await _picker.pickMedia();
    return _toAttachment(picked);
  }

  static Future<PickedAttachment?> _toAttachment(XFile? picked) async {
    if (picked == null) return null;
    final file = File(picked.path);
    final int size = await file.length();
    return PickedAttachment(
      file: file,
      fileName: picked.name,
      fileSizeBytes: size,
      mimeType: picked.mimeType,
    );
  }
}
