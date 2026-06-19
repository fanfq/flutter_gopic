import 'package:flutter/foundation.dart';

enum CloudProvider {
  cloudflareR2,
  awsS3,
  qiniu,
  tencentCos,
  aliyunOss;

  String get label => switch (this) {
    CloudProvider.cloudflareR2 => 'R2',
    CloudProvider.awsS3 => 'S3',
    CloudProvider.qiniu => '七牛云',
    CloudProvider.tencentCos => '腾讯云',
    CloudProvider.aliyunOss => '阿里云',
  };

  bool get supportsS3CompatibleUpload => this != CloudProvider.qiniu;
  bool get supportsUpload => switch (this) {
    CloudProvider.qiniu => true,
    _ => supportsS3CompatibleUpload,
  };

  static CloudProvider fromName(String? value) {
    return CloudProvider.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CloudProvider.cloudflareR2,
    );
  }
}

@immutable
class CompressionSettings {
  const CompressionSettings({
    this.enabled = false,
    this.thresholdBytes = 1024 * 1024,
    this.quality = 70,
  });

  final bool enabled;
  final int thresholdBytes;
  final int quality;

  bool shouldCompress(int sizeBytes) => enabled && sizeBytes > thresholdBytes;

  CompressionSettings copyWith({
    bool? enabled,
    int? thresholdBytes,
    int? quality,
  }) {
    return CompressionSettings(
      enabled: enabled ?? this.enabled,
      thresholdBytes: thresholdBytes ?? this.thresholdBytes,
      quality: (quality ?? this.quality).clamp(1, 100),
    );
  }

  factory CompressionSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CompressionSettings();
    return CompressionSettings(
      enabled: (map['enabled'] as bool?) ?? false,
      thresholdBytes: (map['thresholdBytes'] as num?)?.round() ?? 1024 * 1024,
      quality: ((map['quality'] as num?)?.round() ?? 70).clamp(1, 100),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'thresholdBytes': thresholdBytes,
    'quality': quality,
  };
}

@immutable
class CloudProfile {
  const CloudProfile({
    required this.id,
    required this.provider,
    required this.name,
    this.isEnabled = false,
    this.accountId = '',
    this.accessKeyId = '',
    this.secretAccessKey = '',
    this.bucket = '',
    this.endpoint = '',
    this.publicDomain = '',
    this.pathPrefix = '',
    this.region = 'auto',
    this.usePathStyle = true,
  });

  final String id;
  final CloudProvider provider;
  final String name;
  final bool isEnabled;
  final String accountId;
  final String accessKeyId;
  final String secretAccessKey;
  final String bucket;
  final String endpoint;
  final String publicDomain;
  final String pathPrefix;
  final String region;
  final bool usePathStyle;

  bool get isUploadSupported => provider.supportsUpload;

  bool get isConfigured {
    if (!isEnabled || !isUploadSupported) return false;
    if (provider == CloudProvider.qiniu && publicDomain.trim().isEmpty) {
      return false;
    }
    return accessKeyId.trim().isNotEmpty &&
        secretAccessKey.trim().isNotEmpty &&
        bucket.trim().isNotEmpty &&
        endpoint.trim().isNotEmpty;
  }

  String get endpointHost {
    final ep = endpoint.trim();
    if (ep.isEmpty) return '';
    var host = ep.replaceFirst(RegExp(r'^https?://'), '');
    host = host.split('/').first;
    return host;
  }

  CloudProfile copyWith({
    String? id,
    CloudProvider? provider,
    String? name,
    bool? isEnabled,
    String? accountId,
    String? accessKeyId,
    String? secretAccessKey,
    String? bucket,
    String? endpoint,
    String? publicDomain,
    String? pathPrefix,
    String? region,
    bool? usePathStyle,
  }) {
    return CloudProfile(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      accountId: accountId ?? this.accountId,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      secretAccessKey: secretAccessKey ?? this.secretAccessKey,
      bucket: bucket ?? this.bucket,
      endpoint: endpoint ?? this.endpoint,
      publicDomain: publicDomain ?? this.publicDomain,
      pathPrefix: pathPrefix ?? this.pathPrefix,
      region: region ?? this.region,
      usePathStyle: usePathStyle ?? this.usePathStyle,
    );
  }

  factory CloudProfile.fromMap(Map<String, dynamic> map) {
    return CloudProfile(
      id: (map['id'] as String?) ?? _newProfileId(),
      provider: CloudProvider.fromName(map['provider'] as String?),
      name: (map['name'] as String?) ?? '默认配置',
      isEnabled: (map['isEnabled'] as bool?) ?? false,
      accountId: (map['accountId'] as String?) ?? '',
      accessKeyId: (map['accessKeyId'] as String?) ?? '',
      secretAccessKey: (map['secretAccessKey'] as String?) ?? '',
      bucket: (map['bucket'] as String?) ?? '',
      endpoint: (map['endpoint'] as String?) ?? '',
      publicDomain: (map['publicDomain'] as String?) ?? '',
      pathPrefix: (map['pathPrefix'] as String?) ?? '',
      region: (map['region'] as String?) ?? 'auto',
      usePathStyle: (map['usePathStyle'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'provider': provider.name,
    'name': name,
    'isEnabled': isEnabled,
    'accountId': accountId,
    'accessKeyId': accessKeyId,
    'secretAccessKey': secretAccessKey,
    'bucket': bucket,
    'endpoint': endpoint,
    'publicDomain': publicDomain,
    'pathPrefix': pathPrefix,
    'region': region,
    'usePathStyle': usePathStyle,
  };
}

/// Cloud upload settings, persisted locally and exposed to the UI.
class SettingsModel extends ChangeNotifier {
  SettingsModel() {
    _profiles = _emptyProfiles();
  }

  List<CloudProfile> _profiles = [];
  String? _activeProfileId;
  CompressionSettings _compression = const CompressionSettings();

  List<CloudProfile> get profiles => List.unmodifiable(_profiles);
  List<CloudProfile> get selectableProfiles => _profiles
      .where((p) => p.isEnabled && p.isUploadSupported)
      .toList(growable: false);
  List<CloudProfile> get enabledProfiles => _profiles
      .where((p) => p.isEnabled && p.isConfigured)
      .toList(growable: false);
  CompressionSettings get compression => _compression;
  String? get activeProfileId => activeProfile?.id;

  CloudProfile? get activeProfile {
    final selectable = selectableProfiles;
    if (selectable.isEmpty) return null;
    return selectable.firstWhere(
      (p) => p.id == _activeProfileId,
      orElse: () => selectable.first,
    );
  }

  bool get isConfigured => activeProfile?.isConfigured ?? false;

  // Legacy getters kept so older screens/services can transition safely.
  String get accountId => activeProfile?.accountId ?? '';
  String get accessKeyId => activeProfile?.accessKeyId ?? '';
  String get secretAccessKey => activeProfile?.secretAccessKey ?? '';
  String get bucket => activeProfile?.bucket ?? '';
  String get endpoint => activeProfile?.endpoint ?? '';
  String get publicDomain => activeProfile?.publicDomain ?? '';
  String get pathPrefix => activeProfile?.pathPrefix ?? '';
  bool get usePathStyle => activeProfile?.usePathStyle ?? true;
  String get endpointHost => activeProfile?.endpointHost ?? '';

  List<CloudProfile> profilesFor(CloudProvider provider) =>
      _profiles.where((p) => p.provider == provider).toList(growable: false);

  ({int enabled, int total}) profileCountFor(CloudProvider provider) {
    final profiles = profilesFor(provider);
    return (
      enabled: profiles.where((p) => p.isEnabled).length,
      total: profiles.length,
    );
  }

  String providerMenuLabel(CloudProvider provider) {
    final count = profileCountFor(provider);
    return '${provider.label} (${count.enabled}/${count.total})';
  }

  void loadFromMap(Map<String, dynamic> map) {
    final rawProfiles = map['profiles'];
    if (rawProfiles is List) {
      _profiles = rawProfiles
          .whereType<Map>()
          .map((p) => CloudProfile.fromMap(Map<String, dynamic>.from(p)))
          .toList();
      if (_profiles.isEmpty) _profiles = _emptyProfiles();
      _activeProfileId = map['activeProfileId'] as String?;
    } else {
      _profiles = [_legacyR2Profile(map)];
      _activeProfileId = _profiles.first.id;
    }
    _compression = CompressionSettings.fromMap(
      map['compression'] is Map
          ? Map<String, dynamic>.from(map['compression'] as Map)
          : null,
    );
    _ensureProviderPlaceholders();
    _repairActiveProfile();
    notifyListeners();
  }

  Map<String, dynamic> toMap() => {
    'profiles': _profiles.map((p) => p.toMap()).toList(),
    'activeProfileId': _activeProfileId,
    'compression': _compression.toMap(),
  };

  void setCompression(CompressionSettings value) {
    _compression = value;
    notifyListeners();
  }

  void setActiveProfile(String? profileId) {
    _activeProfileId = profileId;
    _repairActiveProfile();
    notifyListeners();
  }

  void upsertProfile(CloudProfile profile) {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index == -1) {
      _profiles = [..._profiles, profile];
    } else {
      _profiles = [..._profiles]..[index] = profile;
    }
    _repairActiveProfile();
    notifyListeners();
  }

  void deleteProfile(String profileId) {
    _profiles = _profiles.where((p) => p.id != profileId).toList();
    if (_activeProfileId == profileId) {
      _activeProfileId = null;
    }
    _repairActiveProfile();
    notifyListeners();
  }

  void addProfile(CloudProvider provider) {
    final count = profilesFor(provider).length + 1;
    upsertProfile(
      CloudProfile(
        id: _newProfileId(),
        provider: provider,
        name: '${provider.label} $count',
        region: provider == CloudProvider.cloudflareR2 ? 'auto' : 'us-east-1',
      ),
    );
  }

  // Legacy update path: update active profile as an S3-compatible config.
  void update({
    String? accountId,
    String? accessKeyId,
    String? secretAccessKey,
    String? bucket,
    String? endpoint,
    String? publicDomain,
    String? pathPrefix,
    bool? usePathStyle,
  }) {
    final current = activeProfile ?? _profiles.first;
    upsertProfile(
      current.copyWith(
        accountId: accountId,
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        bucket: bucket,
        endpoint: endpoint,
        publicDomain: publicDomain,
        pathPrefix: pathPrefix,
        usePathStyle: usePathStyle,
        isEnabled: true,
      ),
    );
  }

  void _repairActiveProfile() {
    final selectable = selectableProfiles;
    if (selectable.isEmpty) {
      _activeProfileId = null;
      return;
    }
    if (!selectable.any((p) => p.id == _activeProfileId)) {
      _activeProfileId = selectable.first.id;
    }
  }

  void _ensureProviderPlaceholders() {
    final next = [..._profiles];
    for (final provider in CloudProvider.values) {
      if (!next.any((p) => p.provider == provider)) {
        next.add(
          CloudProfile(
            id: _newProfileId(),
            provider: provider,
            name: '${provider.label} 1',
            region: provider == CloudProvider.cloudflareR2
                ? 'auto'
                : 'us-east-1',
          ),
        );
      }
    }
    _profiles = next;
  }

  List<CloudProfile> _emptyProfiles() {
    return CloudProvider.values
        .map(
          (provider) => CloudProfile(
            id: _newProfileId(),
            provider: provider,
            name: '${provider.label} 1',
            region: provider == CloudProvider.cloudflareR2
                ? 'auto'
                : 'us-east-1',
          ),
        )
        .toList();
  }

  CloudProfile _legacyR2Profile(Map<String, dynamic> map) {
    return CloudProfile(
      id: 'cloudflare-r2-default',
      provider: CloudProvider.cloudflareR2,
      name: 'R2 1',
      isEnabled: true,
      accountId: (map['accountId'] as String?) ?? '',
      accessKeyId: (map['accessKeyId'] as String?) ?? '',
      secretAccessKey: (map['secretAccessKey'] as String?) ?? '',
      bucket: (map['bucket'] as String?) ?? '',
      endpoint: (map['endpoint'] as String?) ?? '',
      publicDomain: (map['publicDomain'] as String?) ?? '',
      pathPrefix: (map['pathPrefix'] as String?) ?? '',
      region: 'auto',
      usePathStyle: (map['usePathStyle'] as bool?) ?? true,
    );
  }
}

int _profileIdCounter = 0;

String _newProfileId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_profileIdCounter++}';
