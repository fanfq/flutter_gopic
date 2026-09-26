import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'aws_signer.dart';
import 'upload_progress.dart';
import 'upload_service.dart';

/// S3 Multipart Upload implementation shared by R2, S3, COS and OSS profiles.
/// It follows the Create -> concurrent UploadPart -> Complete lifecycle and
/// aborts the remote upload on any part failure to avoid orphaned storage.
class S3MultipartUploader {
  static const partSize = 5 * 1024 * 1024;
  static const maxConcurrentParts = 4;

  Future<void> upload({
    required Uri objectUri,
    required String host,
    required String objectKey,
    required List<int> bytes,
    required String contentType,
    required AwsSigV4Signer signer,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    final uploadId = await _create(
      objectUri: objectUri,
      host: host,
      objectKey: objectKey,
      contentType: contentType,
      signer: signer,
    );
    final tracker = UploadProgressTracker();
    try {
      final pending = <Future<_UploadedPart>>[];
      final uploaded = <_UploadedPart>[];
      for (var offset = 0, number = 1; offset < bytes.length; number++) {
        final end = (offset + partSize).clamp(0, bytes.length);
        final partBytes = bytes.sublist(offset, end);
        pending.add(
          _uploadPart(
            objectUri: objectUri,
            host: host,
            objectKey: objectKey,
            uploadId: uploadId,
            number: number,
            bytes: partBytes,
            contentType: contentType,
            signer: signer,
          ).then((part) {
            tracker.addBytes(partBytes.length);
            onProgress?.call(tracker.snapshot(totalBytes: bytes.length));
            return part;
          }),
        );
        offset = end;
        if (pending.length == maxConcurrentParts) {
          uploaded.addAll(await Future.wait(pending));
          pending.clear();
        }
      }
      uploaded.addAll(await Future.wait(pending));
      await _complete(
        objectUri: objectUri,
        host: host,
        objectKey: objectKey,
        uploadId: uploadId,
        parts: uploaded,
        signer: signer,
      );
    } catch (_) {
      await _abort(
        objectUri: objectUri,
        host: host,
        objectKey: objectKey,
        uploadId: uploadId,
        signer: signer,
      );
      rethrow;
    }
  }

  Future<String> _create({
    required Uri objectUri,
    required String host,
    required String objectKey,
    required String contentType,
    required AwsSigV4Signer signer,
  }) async {
    final response = await _request(
      method: 'POST',
      uri: objectUri.replace(queryParameters: {'uploads': ''}),
      headers: signer.signRequest(
        method: 'POST',
        host: host,
        objectKey: objectKey,
        query: 'uploads=',
        contentLength: 0,
        contentType: contentType,
      ),
    );
    final body = await utf8.decodeStream(response);
    final match = RegExp(r'<UploadId>([^<]+)</UploadId>').firstMatch(body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        match == null) {
      throw UploadException(
        '无法创建 S3 分片上传。',
        statusCode: response.statusCode,
        responseBody: body,
      );
    }
    return match.group(1)!;
  }

  Future<_UploadedPart> _uploadPart({
    required Uri objectUri,
    required String host,
    required String objectKey,
    required String uploadId,
    required int number,
    required List<int> bytes,
    required String contentType,
    required AwsSigV4Signer signer,
  }) async {
    final query =
        'partNumber=$number&uploadId=${Uri.encodeQueryComponent(uploadId)}';
    final response = await _request(
      method: 'PUT',
      uri: objectUri.replace(query: query),
      body: bytes,
      headers: signer.signRequest(
        method: 'PUT',
        host: host,
        objectKey: objectKey,
        query: query,
        contentLength: bytes.length,
        contentType: contentType,
      ),
    );
    final body = await utf8.decodeStream(response);
    final etag = response.headers.value(HttpHeaders.etagHeader);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        etag == null) {
      throw UploadException(
        'S3 分片 $number 上传失败。',
        statusCode: response.statusCode,
        responseBody: body,
      );
    }
    return _UploadedPart(number, etag);
  }

  Future<void> _complete({
    required Uri objectUri,
    required String host,
    required String objectKey,
    required String uploadId,
    required List<_UploadedPart> parts,
    required AwsSigV4Signer signer,
  }) async {
    final ordered = [...parts]..sort((a, b) => a.number.compareTo(b.number));
    final xml =
        '<CompleteMultipartUpload>${ordered.map((p) => '<Part><PartNumber>${p.number}</PartNumber><ETag>${_xml(p.etag)}</ETag></Part>').join()}</CompleteMultipartUpload>';
    final query = 'uploadId=${Uri.encodeQueryComponent(uploadId)}';
    final bodyBytes = utf8.encode(xml);
    final response = await _request(
      method: 'POST',
      uri: objectUri.replace(query: query),
      body: bodyBytes,
      headers: signer.signRequest(
        method: 'POST',
        host: host,
        objectKey: objectKey,
        query: query,
        contentLength: bodyBytes.length,
        contentType: 'application/xml',
      ),
    );
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadException(
        'S3 分片合并失败。',
        statusCode: response.statusCode,
        responseBody: body,
      );
    }
  }

  Future<void> _abort({
    required Uri objectUri,
    required String host,
    required String objectKey,
    required String uploadId,
    required AwsSigV4Signer signer,
  }) async {
    final query = 'uploadId=${Uri.encodeQueryComponent(uploadId)}';
    try {
      final response = await _request(
        method: 'DELETE',
        uri: objectUri.replace(query: query),
        headers: signer.signRequest(
          method: 'DELETE',
          host: host,
          objectKey: objectKey,
          query: query,
          contentLength: 0,
          contentType: '',
        ),
      );
      await response.drain();
    } catch (_) {
      /* preserve the original transfer error */
    }
  }

  Future<HttpClientResponse> _request({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final request = await HttpClient().openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    return request.close();
  }

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class _UploadedPart {
  const _UploadedPart(this.number, this.etag);
  final int number;
  final String etag;
}
