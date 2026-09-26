import 'dart:convert';
import 'dart:io';

import 'upload_progress.dart';
import 'upload_service.dart';

/// Qiniu's legacy resumable protocol. Qiniu blocks are limited to 4 MiB, so
/// this intentionally does not reuse the S3 multipart lifecycle.
class QiniuResumableUploader {
  static const blockSize = 4 * 1024 * 1024;
  static const maxConcurrentBlocks = 4;

  /// `mkfile` contexts are a comma-separated text payload per Qiniu v1.
  static const finalizeContentType = 'text/plain';

  /// Qiniu URL-safe Base64 retains padding; it only replaces URL-unsafe chars.
  static String encodeObjectKey(String value) =>
      base64Url.encode(utf8.encode(value));

  Future<void> upload({
    required Uri endpoint,
    required String token,
    required String objectKey,
    required List<int> bytes,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    final contexts = <String>[];
    final tracker = UploadProgressTracker();
    for (
      var offset = 0;
      offset < bytes.length;
      offset += blockSize * maxConcurrentBlocks
    ) {
      final batch = <Future<({String context, int length})>>[];
      for (
        var index = 0;
        index < maxConcurrentBlocks &&
            offset + index * blockSize < bytes.length;
        index++
      ) {
        final start = offset + index * blockSize;
        final end = (start + blockSize).clamp(0, bytes.length);
        batch.add(
          _uploadBlock(
            endpoint: endpoint,
            token: token,
            bytes: bytes.sublist(start, end),
          ),
        );
      }
      final results = await Future.wait(batch);
      for (final result in results) {
        contexts.add(result.context);
        tracker.addBytes(result.length);
        onProgress?.call(tracker.snapshot(totalBytes: bytes.length));
      }
    }
    final encodedKey = encodeObjectKey(objectKey);
    final finalize = endpoint.replace(
      path:
          '${endpoint.path.replaceFirst(RegExp(r'/$'), '')}/mkfile/${bytes.length}/key/$encodedKey',
    );
    final response = await _request(
      finalize,
      token: token,
      body: utf8.encode(contexts.join(',')),
      contentType: finalizeContentType,
    );
    final body = await utf8.decodeStream(response);
    _decode(body, '七牛云分片合并失败', response.statusCode);
  }

  Future<({String context, int length})> _uploadBlock({
    required Uri endpoint,
    required String token,
    required List<int> bytes,
  }) async {
    final response = await _request(
      endpoint.replace(
        path:
            '${endpoint.path.replaceFirst(RegExp(r'/$'), '')}/mkblk/${bytes.length}',
      ),
      token: token,
      body: bytes,
    );
    final body = await utf8.decodeStream(response);
    final json = _decode(body, '七牛云分片上传失败', response.statusCode);
    final ctx = json['ctx'];
    if (ctx is! String || ctx.isEmpty) {
      throw UploadException(
        '七牛云分片响应缺少 ctx。',
        statusCode: response.statusCode,
        responseBody: body,
      );
    }
    return (context: ctx, length: bytes.length);
  }

  Future<HttpClientResponse> _request(
    Uri uri, {
    required String token,
    required List<int> body,
    String contentType = 'application/octet-stream',
  }) async {
    final request = await HttpClient().openUrl('POST', uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'UpToken $token');
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.headers.contentLength = body.length;
    request.add(body);
    return request.close();
  }

  Map<String, dynamic> _decode(String body, String message, int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw UploadException(
        message,
        statusCode: statusCode,
        responseBody: body,
      );
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      throw UploadException(
        '$message：响应格式无效。',
        statusCode: statusCode,
        responseBody: body,
      );
    }
  }
}
