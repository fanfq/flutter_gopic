// Tests for the AWS SigV4 signer. These are pure (no network, no I/O) so they
// run on any platform and catch regressions in the signature algorithm.

import 'package:flutter_gopic/services/aws_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AwsSigV4Signer', () {
    test('signPut produces an Authorization header with the expected shape', () {
      final signer = AwsSigV4Signer(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      );

      final headers = signer.signPut(
        host: 'example.r2.cloudflarestorage.com',
        objectKey: '/my-bucket/hello.jpg',
        contentLength: 1234,
        contentType: 'image/jpeg',
        now: DateTime.utc(2026, 6, 16, 12, 30, 0),
      );

      expect(headers, contains('Authorization'));
      final auth = headers['Authorization']!;
      expect(auth, startsWith('AWS4-HMAC-SHA256 '));
      expect(auth, contains('Credential=AKIAIOSFODNN7EXAMPLE/20260616/auto/s3/aws4_request'));
      expect(auth, contains('SignedHeaders='));
      expect(auth, contains('Signature='));

      // Required headers for UNSIGNED-PAYLOAD signing.
      expect(headers['x-amz-content-sha256'], 'UNSIGNED-PAYLOAD');
      expect(headers['x-amz-date'], '20260616T123000Z');
      expect(headers['content-length'], '1234');
      expect(headers['content-type'], 'image/jpeg');
    });

    test('signing the same inputs twice yields the same signature', () {
      final signer = AwsSigV4Signer(
        accessKeyId: 'AKID',
        secretAccessKey: 'secret',
      );
      final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final a = signer.signPut(
        host: 'h.r2.cloudflarestorage.com',
        objectKey: '/b/名称 1.png',
        contentLength: 0,
        contentType: 'image/png',
        now: now,
      );
      final b = signer.signPut(
        host: 'h.r2.cloudflarestorage.com',
        objectKey: '/b/名称 1.png',
        contentLength: 0,
        contentType: 'image/png',
        now: now,
      );
      expect(a['Signature'] ?? a['Authorization'], b['Signature'] ?? b['Authorization']);
      // Sanity: the signature section is present and 64 hex chars.
      final sig = RegExp(r'Signature=([0-9a-f]+)').firstMatch(a['Authorization']!)!.group(1)!;
      expect(sig.length, 64);
    });
  });
}
