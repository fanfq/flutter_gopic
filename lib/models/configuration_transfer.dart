import 'dart:convert';

import 'cloud_model.dart';

/// Versioned import and export for the locally persisted cloud configuration.
class ConfigurationTransfer {
  ConfigurationTransfer._();

  static const int supportedVersion = 1;

  static String exportJson(CloudModel cloud, {DateTime Function()? clock}) {
    final exportedAt = (clock?.call() ?? DateTime.now()).toUtc();
    return jsonEncode({
      'version': supportedVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'cloud': cloud.toMap(),
    });
  }

  static ({int added}) importJson(String source, CloudModel cloud) {
    final document = _parseAndValidate(source);
    return cloud.mergeFromMap(document['cloud'] as Map<String, dynamic>);
  }

  static Map<String, dynamic> _parseAndValidate(String source) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid configuration JSON: ${error.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('Configuration document must be an object.');
    }
    final document = Map<String, dynamic>.from(decoded);
    if (document['version'] != supportedVersion) {
      throw const FormatException('Unsupported configuration version.');
    }
    _validateExportedAt(document['exportedAt']);
    final cloud = document['cloud'];
    if (cloud is! Map) {
      throw const FormatException('Configuration cloud must be an object.');
    }
    final cloudMap = Map<String, dynamic>.from(cloud);
    _validateCloud(cloudMap);
    return {...document, 'cloud': cloudMap};
  }

  static void _validateExportedAt(Object? value) {
    if (value is! String || !value.endsWith('Z')) {
      throw const FormatException(
        'Configuration export time must be UTC ISO-8601.',
      );
    }
    try {
      if (!DateTime.parse(value).isUtc) {
        throw const FormatException('Configuration export time must be UTC.');
      }
    } on FormatException {
      throw const FormatException('Invalid configuration export time.');
    }
  }

  static void _validateCloud(Map<String, dynamic> cloud) {
    final profiles = cloud['profiles'];
    if (profiles is! List) {
      throw const FormatException('Cloud profiles must be a list.');
    }
    final profileIds = <String>{};
    for (final rawProfile in profiles) {
      if (rawProfile is! Map) {
        throw const FormatException('Cloud profile must be an object.');
      }
      final profile = Map<String, dynamic>.from(rawProfile);
      final id = profile['id'];
      if (id is! String || id.trim().isEmpty) {
        throw const FormatException('Cloud profile id is required.');
      }
      if (!profileIds.add(id)) {
        throw const FormatException('Cloud profile ids must be unique.');
      }
      _validateProfileFields(profile);
    }

    final activeProfileId = cloud['activeProfileId'];
    if (activeProfileId != null && activeProfileId is! String) {
      throw const FormatException('Cloud active profile id must be a string.');
    }
    final compression = cloud['compression'];
    if (compression is! Map) {
      throw const FormatException('Cloud compression must be an object.');
    }
    final compressionMap = Map<String, dynamic>.from(compression);
    if (compressionMap['enabled'] is! bool ||
        compressionMap['thresholdBytes'] is! num ||
        compressionMap['quality'] is! num) {
      throw const FormatException('Cloud compression is invalid.');
    }
  }

  static void _validateProfileFields(Map<String, dynamic> profile) {
    const stringFields = [
      'provider',
      'name',
      'accountId',
      'accessKeyId',
      'secretAccessKey',
      'bucket',
      'endpoint',
      'publicDomain',
      'pathPrefix',
      'region',
    ];
    for (final field in stringFields) {
      final value = profile[field];
      if (value != null && value is! String) {
        throw FormatException('Cloud profile $field must be a string.');
      }
    }
    for (final field in const ['isEnabled', 'usePathStyle']) {
      final value = profile[field];
      if (value != null && value is! bool) {
        throw FormatException('Cloud profile $field must be a boolean.');
      }
    }
  }
}
