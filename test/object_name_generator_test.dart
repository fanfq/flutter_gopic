import 'package:flutter_gopic/models/cloud_model.dart';
import 'package:flutter_gopic/services/object_name_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final generator = ObjectNameGenerator(
    clock: () => DateTime(2026, 6, 20, 12),
    hashFactory: () => 'abc123',
    uuidFactory: () => 'a' * 32,
  );

  test('keeps the legacy dated hash and filename format by default', () {
    expect(
      generator.build(
        pattern: UploadNamingPattern.datedHashFileName,
        fileName: 'secret photo.jpg',
      ),
      '20260620/abc123_secret_photo.jpg',
    );
  });

  test('uses a compact UUID below the date folder', () {
    expect(
      generator.build(
        pattern: UploadNamingPattern.datedUuid,
        fileName: 'secret photo.jpg',
      ),
      '20260620/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg',
    );
  });

  test('uses a compact UUID without a date folder', () {
    expect(
      generator.build(
        pattern: UploadNamingPattern.uuid,
        fileName: 'secret photo.jpg',
      ),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg',
    );
  });
}
