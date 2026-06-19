import 'dart:convert';

import 'package:flutter_gopic/services/qiniu_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QiniuUploadTokenSigner', () {
    test('generates the official upload token sample', () {
      final signer = QiniuUploadTokenSigner(
        accessKey: 'MY_ACCESS_KEY',
        secretKey: 'MY_SECRET_KEY',
      );

      final token = signer.signPutPolicyJson(
        '{"scope":"my-bucket:sunflower.jpg","deadline":1451491200,"returnBody":"{'
        r'\"name\":$(fname),\"size\":$(fsize),\"w\":$(imageInfo.width),\"h\":$(imageInfo.height),\"hash\":$(etag)'
        '}"}',
      );

      expect(
        token,
        'MY_ACCESS_KEY:wQ4ofysef1R7IKnrziqtomqyDvI=:'
        'eyJzY29wZSI6Im15LWJ1Y2tldDpzdW5mbG93ZXIuanBnIiwiZGVhZGxpbmUiOjE0NTE0OTEyMDAsInJldHVybkJvZHkiOiJ7XCJuYW1lXCI6JChmbmFtZSksXCJzaXplXCI6JChmc2l6ZSksXCJ3XCI6JChpbWFnZUluZm8ud2lkdGgpLFwiaFwiOiQoaW1hZ2VJbmZvLmhlaWdodCksXCJoYXNoXCI6JChldGFnKX0ifQ==',
      );
    });

    test('builds a scoped token for a specific object key', () {
      final signer = QiniuUploadTokenSigner(accessKey: 'ak', secretKey: 'sk');

      final token = signer.signUploadToken(
        bucket: 'images',
        objectKey: '20260616/a.png',
        deadline: 1780000000,
      );

      expect(token, startsWith('ak:'));
      final parts = token.split(':');
      expect(parts, hasLength(3));
      final policy =
          jsonDecode(
                utf8.decode(base64Url.decode(signer.lastEncodedPolicyForTest!)),
              )
              as Map<String, dynamic>;
      expect(policy['scope'], 'images:20260616/a.png');
      expect(policy['deadline'], 1780000000);
    });
  });
}
