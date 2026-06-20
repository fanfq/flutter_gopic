import 'dart:io';

import 'package:flutter_gopic/models/cloud_model.dart';
import 'package:flutter_gopic/services/image_compression_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'prepares original file when compression is disabled or under threshold',
    () async {
      final temp = await Directory.systemTemp.createTemp('gopic_compress_test');
      final file = File('${temp.path}/sample.jpg');
      final image = img.Image(width: 64, height: 64);
      await file.writeAsBytes(img.encodeJpg(image, quality: 90));

      final service = ImageCompressionService();
      final disabled = await service.prepare(
        file,
        const CompressionConfig(enabled: false, thresholdBytes: 1, quality: 50),
      );
      final underThreshold = await service.prepare(
        file,
        CompressionConfig(
          enabled: true,
          thresholdBytes: await file.length() + 1,
          quality: 50,
        ),
      );

      expect(disabled.wasCompressed, isFalse);
      expect(underThreshold.wasCompressed, isFalse);
      expect(disabled.bytes, await file.readAsBytes());
      await temp.delete(recursive: true);
    },
  );

  test('compresses supported raster images above threshold', () async {
    final temp = await Directory.systemTemp.createTemp('gopic_compress_test');
    final file = File('${temp.path}/sample.jpg');
    final image = img.Image(width: 640, height: 640);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
      }
    }
    await file.writeAsBytes(img.encodeJpg(image, quality: 95));

    final result = await ImageCompressionService().prepare(
      file,
      const CompressionConfig(enabled: true, thresholdBytes: 1, quality: 40),
    );

    expect(result.wasCompressed, isTrue);
    expect(result.contentType, 'image/jpeg');
    expect(result.fileName.endsWith('.jpg'), isTrue);
    expect(result.bytes.length, lessThan(await file.length()));
    await temp.delete(recursive: true);
  });
}
