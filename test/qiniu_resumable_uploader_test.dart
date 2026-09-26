import 'package:flutter_gopic/services/qiniu_resumable_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps URL-safe Base64 padding for the mkfile object key', () {
    expect(QiniuResumableUploader.encodeObjectKey('myObject'), 'bXlPYmplY3Q=');
  });

  test('uses the required text content type for mkfile context bodies', () {
    expect(QiniuResumableUploader.finalizeContentType, 'text/plain');
  });
}
