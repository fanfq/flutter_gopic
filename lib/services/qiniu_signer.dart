import 'dart:convert';

import 'package:crypto/crypto.dart';

class QiniuUploadTokenSigner {
  QiniuUploadTokenSigner({required this.accessKey, required this.secretKey});

  final String accessKey;
  final String secretKey;

  String? _lastEncodedPolicyForTest;
  String? get lastEncodedPolicyForTest => _lastEncodedPolicyForTest;

  String signUploadToken({
    required String bucket,
    required String objectKey,
    required int deadline,
  }) {
    final policy = jsonEncode({
      'scope': '$bucket:$objectKey',
      'deadline': deadline,
    });
    return signPutPolicyJson(policy);
  }

  String signPutPolicyJson(String putPolicyJson) {
    final encodedPolicy = base64UrlEncode(utf8.encode(putPolicyJson));
    _lastEncodedPolicyForTest = encodedPolicy;
    final sign = Hmac(
      sha1,
      utf8.encode(secretKey),
    ).convert(utf8.encode(encodedPolicy));
    final encodedSign = base64UrlEncode(sign.bytes);
    return '$accessKey:$encodedSign:$encodedPolicy';
  }
}
