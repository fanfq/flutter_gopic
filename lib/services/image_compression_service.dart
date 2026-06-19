import 'dart:io';

import 'package:image/image.dart' as img;

import '../models/settings_model.dart';

class PreparedImageUpload {
  const PreparedImageUpload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.wasCompressed,
  });

  final List<int> bytes;
  final String fileName;
  final String contentType;
  final bool wasCompressed;
}

class ImageCompressionService {
  Future<PreparedImageUpload> prepare(
    File file,
    CompressionSettings settings,
  ) async {
    final originalBytes = await file.readAsBytes();
    final originalName = _basename(file.path);
    final originalType = _guessContentType(file.path);
    final original = PreparedImageUpload(
      bytes: originalBytes,
      fileName: originalName,
      contentType: originalType,
      wasCompressed: false,
    );

    if (!settings.shouldCompress(originalBytes.length)) return original;
    if (!_canCompress(file.path)) return original;

    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return original;
      final encoded = img.encodeJpg(decoded, quality: settings.quality);
      if (encoded.length >= originalBytes.length) return original;
      return PreparedImageUpload(
        bytes: encoded,
        fileName: _replaceExtension(originalName, 'jpg'),
        contentType: 'image/jpeg',
        wasCompressed: true,
      );
    } catch (_) {
      return original;
    }
  }

  bool _canCompress(String path) {
    final ext = _extension(path);
    return const {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'bmp',
      'tif',
      'tiff',
    }.contains(ext);
  }

  String _replaceExtension(String name, String extension) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '$name.$extension';
    return '${name.substring(0, dot)}.$extension';
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  String _extension(String path) {
    final base = _basename(path);
    final dot = base.lastIndexOf('.');
    if (dot == -1 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  String _guessContentType(String path) {
    switch (_extension(path)) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'tiff':
      case 'tif':
        return 'image/tiff';
      case 'ico':
        return 'image/x-icon';
      case 'avif':
        return 'image/avif';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
}
