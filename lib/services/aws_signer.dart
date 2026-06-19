import 'dart:convert';

import 'package:crypto/crypto.dart';

/// AWS Signature Version 4 signer for S3-compatible APIs (Cloudflare R2).
///
/// We sign a PUT request using the `UNSIGNED-PAYLOAD` value for the
/// `x-amz-content-sha256` header. This avoids needing to hash the entire body
/// into memory — ideal for streaming large files from disk.
class AwsSigV4Signer {
  AwsSigV4Signer({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.region = 'auto',
    this.service = 's3',
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final String service;

  static const _algorithm = 'AWS4-HMAC-SHA256';
  static const _unsignedPayload = 'UNSIGNED-PAYLOAD';

  /// Builds the headers needed for a signed PUT request.
  ///
  /// [host] is the endpoint host (e.g. `<accountid>.r2.cloudflarestorage.com`).
  /// [objectKey] is the URL path beginning with `/` (already URL-encoded where
  /// necessary). [contentLength] is the byte length of the body.
  Map<String, String> signPut({
    required String host,
    required String objectKey,
    required int contentLength,
    required String contentType,
    String? token,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now().toUtc();
    final amzDate = _amzDate(t);
    final dateStamp = _dateStamp(t);

    final canonicalUri = _canonicalUri(objectKey);
    final canonicalQueryString = '';

    // Headers must be lowercase and sorted for the canonical request.
    final headers = <String, String>{
      'host': host,
      'x-amz-content-sha256': _unsignedPayload,
      'x-amz-date': amzDate,
      'content-length': '$contentLength',
      'content-type': contentType,
      if (token != null && token.isNotEmpty) 'x-amz-security-token': token,
    }..removeWhere((_, v) => v.isEmpty);

    final sortedHeaders = headers.keys.toList()..sort();
    final canonicalHeaders =
        sortedHeaders.map((k) => '$k:${headers[k]!.trim()}\n').join();
    final signedHeaders = sortedHeaders.join(';');

    final canonicalRequest = [
      'PUT',
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      _unsignedPayload,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      _algorithm,
      amzDate,
      credentialScope,
      _hex(sha256.convert(utf8.encode(canonicalRequest))),
    ].join('\n');

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = _hmacHex(signingKey, utf8.encode(stringToSign));

    final authorization = [
      '$_algorithm '
          'Credential=$accessKeyId/$credentialScope',
      'SignedHeaders=$signedHeaders',
      'Signature=$signature',
    ].join(', ');

    return {
      'Authorization': authorization,
      'x-amz-content-sha256': _unsignedPayload,
      'x-amz-date': amzDate,
      'content-type': contentType,
      'content-length': '$contentLength',
      'host': host,
      if (token != null && token.isNotEmpty) 'x-amz-security-token': token,
    };
  }

  String _canonicalUri(String objectKey) {
    // Path must be URL-encoded except for the slashes that separate segments.
    // R2 keys may contain spaces / unicode; encode each segment individually.
    if (!objectKey.startsWith('/')) objectKey = '/$objectKey';
    if (objectKey == '/') return '/';
    final segments = objectKey
        .split('/')
        .map((s) => s.isEmpty ? '' : _encodeSegment(s));
    return segments.join('/');
  }

  String _encodeSegment(String s) {
    // Reserve unreserved chars; encode the rest as %HH (uppercase).
    final out = StringBuffer();
    final bytes = utf8.encode(s);
    for (final b in bytes) {
      if ((b >= 0x30 && b <= 0x39) || // 0-9
          (b >= 0x41 && b <= 0x5A) || // A-Z
          (b >= 0x61 && b <= 0x7A) || // a-z
          b == 0x2D || // -
          b == 0x2E || // .
          b == 0x5F || // _
          b == 0x7E) {
        out.writeCharCode(b);
      } else {
        out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  List<int> _deriveSigningKey(String dateStamp) {
    final kDate = _hmac(utf8.encode('AWS4$secretAccessKey'), utf8.encode(dateStamp));
    final kRegion = _hmac(kDate, utf8.encode(region));
    final kService = _hmac(kRegion, utf8.encode(service));
    return _hmac(kService, utf8.encode('aws4_request'));
  }

  List<int> _hmac(List<int> key, List<int> data) {
    final hmacSha256 = Hmac(sha256, key);
    return hmacSha256.convert(data).bytes;
  }

  String _hmacHex(List<int> key, List<int> data) =>
      _hex(Hmac(sha256, key).convert(data));

  String _hex(Digest d) => d.toString();

  String _amzDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}T${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}Z';

  String _dateStamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
}
