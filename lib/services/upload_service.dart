import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/history_model.dart';
import '../models/cloud_model.dart';
import 'aws_signer.dart';
import 'history_service.dart';
import 'image_compression_service.dart';
import 'object_name_generator.dart';
import 'qiniu_signer.dart';
import 'cloud_service.dart';

class UploadResult {
  final String url;
  final String objectKey;
  UploadResult(this.url, this.objectKey);
}

class UploadException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;
  UploadException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'UploadException($statusCode): $message';
}

/// Orchestrates uploads to Cloudflare R2 via its S3-compatible API.
class UploadService {
  UploadService({
    required this.cloudService,
    required this.historyService,
    ImageCompressionService? imageCompressionService,
    ObjectNameGenerator? objectNameGenerator,
  }) : imageCompressionService =
           imageCompressionService ?? ImageCompressionService(),
       objectNameGenerator = objectNameGenerator ?? ObjectNameGenerator();

  final CloudService cloudService;
  final HistoryService historyService;
  final ImageCompressionService imageCompressionService;
  final ObjectNameGenerator objectNameGenerator;

  CloudModel get _cloud => cloudService.model;

  CloudProfile _requireProfile() {
    final profile = _cloud.activeProfile;
    if (profile == null) {
      throw UploadException('尚未启用可用的云服务配置，请在「云服务」中启用并填写参数。');
    }
    if (!profile.isUploadSupported) {
      throw UploadException('${profile.provider.label} 暂未接入上传协议。');
    }
    if (!profile.isConfigured) {
      throw UploadException(
        '${profile.name} 配置不完整，请检查 Access Key、Secret、Bucket 和 Endpoint。',
      );
    }
    return profile;
  }

  /// Upload a local file to the active cloud profile. Returns the public URL and object key.
  Future<UploadResult> uploadFile(File file) async {
    final profile = _requireProfile();

    final prepared = await imageCompressionService.prepare(
      file,
      _cloud.compression,
    );
    final bytes = prepared.bytes;
    final size = bytes.length;
    final contentType = prepared.contentType;
    if (profile.provider == CloudProvider.qiniu) {
      return _uploadQiniu(
        file: file,
        profile: profile,
        fileName: prepared.fileName,
        bytes: bytes,
        size: size,
        contentType: contentType,
      );
    }

    final objectKey = _buildS3ObjectKey(profile, prepared.fileName);

    final host = profile.endpointHost;
    if (host.isEmpty) {
      throw UploadException('Endpoint 无效，无法解析主机名。');
    }

    final signer = AwsSigV4Signer(
      accessKeyId: profile.accessKeyId.trim(),
      secretAccessKey: profile.secretAccessKey.trim(),
      region: profile.region.trim().isEmpty ? 'auto' : profile.region.trim(),
    );

    final headers = signer.signPut(
      host: host,
      objectKey: objectKey,
      contentLength: size,
      contentType: contentType,
    );

    final uri = Uri.parse(
      '${profile.endpoint.trim().replaceAll(RegExp(r'/+$'), '')}$objectKey',
    );

    HttpClient? client;
    try {
      client = HttpClient();
      // Cloudflare R2 supports path-style: https://<account>.r2.cloudflarestorage.com/<bucket>/<key>
      final request = await client.openUrl('PUT', uri);
      headers.forEach((k, v) => request.headers.set(k, v));
      request.add(bytes);
      final response = await request.close();

      final body = await _readResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UploadException(
          '上传失败 (HTTP ${response.statusCode})。',
          statusCode: response.statusCode,
          responseBody: body,
        );
      }

      final url = _buildPublicUrl(profile, objectKey);

      // Mirror locally for gallery thumbnails.
      String? localPath;
      try {
        localPath = await historyService.cacheFile(
          file.path,
          _basename(file.path),
        );
      } catch (_) {
        // Non-fatal: gallery will just hide the thumbnail.
      }

      final item = HistoryItem(
        id: _newId(),
        fileName: prepared.fileName,
        objectKey: objectKey,
        url: url,
        sizeBytes: size,
        contentType: contentType,
        uploadedAt: DateTime.now(),
        localThumbPath: localPath,
        cloudProfileId: profile.id,
        cloudProvider: profile.provider,
      );
      await historyService.add(item);

      return UploadResult(url, objectKey);
    } on UploadException {
      rethrow;
    } catch (e) {
      throw UploadException('发生未知错误: $e');
    } finally {
      client?.close();
    }
  }

  /// Build the S3-compatible object key: optional prefix + selected object name.
  String _buildS3ObjectKey(CloudProfile profile, String fileName) {
    return '/${profile.bucket.trim()}/${_buildObjectName(profile, fileName)}';
  }

  String _buildObjectName(CloudProfile profile, String fileName) {
    final prefix = profile.pathPrefix.trim();
    final segments = <String>[];
    if (prefix.isNotEmpty) {
      segments.add(prefix.replaceAll(RegExp(r'^/+|/+$'), ''));
    }
    segments.add(
      objectNameGenerator.build(
        pattern: _cloud.uploadNamingPattern,
        fileName: fileName,
      ),
    );
    return segments.where((s) => s.isNotEmpty).join('/');
  }

  Future<UploadResult> _uploadQiniu({
    required File file,
    required CloudProfile profile,
    required String fileName,
    required List<int> bytes,
    required int size,
    required String contentType,
  }) async {
    final objectKey = _buildObjectName(profile, fileName);
    final endpoint = profile.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    if (endpoint.isEmpty) {
      throw UploadException('七牛云上传域名不能为空。');
    }

    final token =
        QiniuUploadTokenSigner(
          accessKey: profile.accessKeyId.trim(),
          secretKey: profile.secretAccessKey.trim(),
        ).signUploadToken(
          bucket: profile.bucket.trim(),
          objectKey: objectKey,
          deadline: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        );

    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.openUrl('POST', Uri.parse(endpoint));
      final boundary = '----gopic-${_randomToken(18)}';
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      final body = _buildMultipartBody(
        boundary: boundary,
        fields: {'key': objectKey, 'token': token},
        fileFieldName: 'file',
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      );
      request.headers.set(HttpHeaders.contentLengthHeader, body.length);
      request.add(body);
      final response = await request.close();
      final responseBody = await _readResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UploadException(
          '七牛云上传失败 (HTTP ${response.statusCode})。',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final url = _buildQiniuPublicUrl(profile, objectKey);
      String? localPath;
      try {
        localPath = await historyService.cacheFile(
          file.path,
          _basename(file.path),
        );
      } catch (_) {
        // Non-fatal: gallery will just hide the thumbnail.
      }

      final item = HistoryItem(
        id: _newId(),
        fileName: fileName,
        objectKey: objectKey,
        url: url,
        sizeBytes: size,
        contentType: contentType,
        uploadedAt: DateTime.now(),
        localThumbPath: localPath,
        cloudProfileId: profile.id,
        cloudProvider: profile.provider,
      );
      await historyService.add(item);

      return UploadResult(url, objectKey);
    } on UploadException {
      rethrow;
    } catch (e) {
      throw UploadException('七牛云上传发生未知错误: $e');
    } finally {
      client?.close();
    }
  }

  List<int> _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required String fileFieldName,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) {
    final body = <int>[];
    void addAscii(String value) => body.addAll(utf8.encode(value));

    for (final entry in fields.entries) {
      addAscii('--$boundary\r\n');
      addAscii('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
      addAscii('${entry.value}\r\n');
    }

    addAscii('--$boundary\r\n');
    addAscii(
      'Content-Disposition: form-data; name="$fileFieldName"; filename="$fileName"\r\n',
    );
    addAscii('Content-Type: $contentType\r\n');
    addAscii('Content-Transfer-Encoding: binary\r\n\r\n');
    body.addAll(bytes);
    addAscii('\r\n--$boundary--\r\n');
    return body;
  }

  String _buildQiniuPublicUrl(CloudProfile profile, String objectKey) {
    final domain = profile.publicDomain.trim();
    if (domain.isEmpty) {
      throw UploadException('七牛云需要填写公网 URL 前缀，用于生成上传后的访问链接。');
    }
    final d = domain.replaceAll(RegExp(r'/+$'), '');
    return '$d/${objectKey.replaceAll(RegExp(r'^/+'), '')}';
  }

  String _buildPublicUrl(CloudProfile profile, String objectKey) {
    final domain = profile.publicDomain.trim();
    if (domain.isNotEmpty) {
      final d = domain.replaceAll(RegExp(r'/+$'), '');
      // Object key includes leading "/<bucket>"; for custom domain we usually
      // expose just the key portion after the bucket.
      final afterBucket = _stripBucketFromKey(profile, objectKey);
      return '$d$afterBucket';
    }
    // Fall back to the R2 URL.
    final ep = profile.endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    return '$ep$objectKey';
  }

  String _stripBucketFromKey(CloudProfile profile, String objectKey) {
    final bucket = profile.bucket.trim();
    var k = objectKey;
    if (bucket.isNotEmpty && k.startsWith('/$bucket')) {
      k = k.substring(bucket.length + 1);
    }
    return k;
  }

  Future<String> _readResponse(HttpClientResponse response) async {
    try {
      final body = <int>[];
      await for (final chunk in response) {
        body.addAll(chunk);
      }
      return String.fromCharCodes(body);
    } catch (_) {
      return '';
    }
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$ts${_randomToken(4)}';
  }

  String _randomToken(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    final out = StringBuffer();
    for (var i = 0; i < len; i++) {
      out.write(chars[rng.nextInt(chars.length)]);
    }
    return out.toString();
  }
}
