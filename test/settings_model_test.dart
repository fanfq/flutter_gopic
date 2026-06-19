import 'package:flutter_gopic/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads legacy R2 settings as an enabled Cloudflare R2 profile', () {
    final model = SettingsModel()
      ..loadFromMap({
        'accountId': 'acc',
        'accessKeyId': 'ak',
        'secretAccessKey': 'sk',
        'bucket': 'bucket',
        'endpoint': 'https://acc.r2.cloudflarestorage.com',
        'publicDomain': 'https://cdn.test',
        'pathPrefix': 'images',
      });

    expect(
      model.profiles.map((p) => p.provider),
      contains(CloudProvider.cloudflareR2),
    );
    expect(model.activeProfile?.provider, CloudProvider.cloudflareR2);
    expect(model.activeProfile?.isEnabled, isTrue);
    expect(model.activeProfile?.bucket, 'bucket');
    expect(model.isConfigured, isTrue);
  });

  test(
    'active profile falls back to another enabled profile and compression obeys threshold',
    () {
      final disabled = CloudProfile(
        id: 'r2',
        provider: CloudProvider.cloudflareR2,
        name: 'R2',
        isEnabled: false,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://r2.example.com',
      );
      final enabled = disabled.copyWith(
        id: 'aws',
        provider: CloudProvider.awsS3,
        name: 'AWS',
        isEnabled: true,
        endpoint: 'https://s3.us-east-1.amazonaws.com',
      );
      final model = SettingsModel()
        ..loadFromMap({
          'activeProfileId': 'r2',
          'profiles': [disabled.toMap(), enabled.toMap()],
          'compression': {
            'enabled': true,
            'thresholdBytes': 1024 * 1024,
            'quality': 70,
          },
        });

      expect(model.activeProfile?.id, 'aws');
      expect(model.enabledProfiles.map((p) => p.id), ['aws']);
      expect(model.compression.shouldCompress(1024 * 1024), isFalse);
      expect(model.compression.shouldCompress(1024 * 1024 + 1), isTrue);
      expect(model.compression.quality, 70);
    },
  );

  test(
    'profiles can be deleted and enabling a profile does not make it default',
    () {
      final selected = CloudProfile(
        id: 'selected',
        provider: CloudProvider.cloudflareR2,
        name: 'Selected',
        isEnabled: true,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://r2.example.com',
      );
      final another = selected.copyWith(id: 'another', name: 'Another');
      final model = SettingsModel()
        ..loadFromMap({
          'activeProfileId': 'selected',
          'profiles': [
            selected.toMap(),
            another.copyWith(isEnabled: false).toMap(),
          ],
        });

      model.upsertProfile(another.copyWith(isEnabled: true));

      expect(model.activeProfile?.id, 'selected');

      model.deleteProfile('selected');

      expect(model.profiles.map((p) => p.id), isNot(contains('selected')));
      expect(model.activeProfile?.id, 'another');
    },
  );

  test('provider count text shows enabled profiles over total profiles', () {
    final enabled = CloudProfile(
      id: 'enabled',
      provider: CloudProvider.cloudflareR2,
      name: 'Enabled',
      isEnabled: true,
    );
    final disabled = enabled.copyWith(id: 'disabled', isEnabled: false);
    final model = SettingsModel()
      ..loadFromMap({
        'profiles': [enabled.toMap(), disabled.toMap()],
      });

    expect(model.profileCountFor(CloudProvider.cloudflareR2), (
      enabled: 1,
      total: 2,
    ));
    expect(model.providerMenuLabel(CloudProvider.cloudflareR2), 'R2 (1/2)');
    expect(model.providerMenuLabel(CloudProvider.awsS3), 'S3 (0/1)');
  });

  test(
    'enabled Qiniu profile is considered upload-ready when required fields exist',
    () {
      final qiniu = CloudProfile(
        id: 'qiniu',
        provider: CloudProvider.qiniu,
        name: 'Qiniu',
        isEnabled: true,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://up-z0.qiniup.com',
        publicDomain: 'https://cdn.example.com',
      );
      final model = SettingsModel()
        ..loadFromMap({
          'activeProfileId': 'qiniu',
          'profiles': [qiniu.toMap()],
        });

      expect(qiniu.isUploadSupported, isTrue);
      expect(qiniu.isConfigured, isTrue);
      expect(model.activeProfile?.provider, CloudProvider.qiniu);
      expect(model.isConfigured, isTrue);
    },
  );

  test('Qiniu profile requires a public URL prefix to be upload-ready', () {
    final qiniu = CloudProfile(
      id: 'qiniu',
      provider: CloudProvider.qiniu,
      name: 'Qiniu',
      isEnabled: true,
      accessKeyId: 'ak',
      secretAccessKey: 'sk',
      bucket: 'bucket',
      endpoint: 'https://up-z0.qiniup.com',
    );

    expect(qiniu.isConfigured, isFalse);
  });

  test('enabled but incomplete Qiniu profile remains selectable', () {
    final qiniu = CloudProfile(
      id: 'qiniu',
      provider: CloudProvider.qiniu,
      name: 'Qiniu',
      isEnabled: true,
      accessKeyId: 'ak',
      secretAccessKey: 'sk',
      bucket: 'bucket',
      endpoint: 'https://up-z0.qiniup.com',
    );
    final r2 = CloudProfile(
      id: 'r2',
      provider: CloudProvider.cloudflareR2,
      name: 'R2',
      isEnabled: true,
      accessKeyId: 'ak',
      secretAccessKey: 'sk',
      bucket: 'bucket',
      endpoint: 'https://r2.example.com',
    );
    final model = SettingsModel()
      ..loadFromMap({
        'activeProfileId': 'qiniu',
        'profiles': [qiniu.toMap(), r2.toMap()],
      });

    expect(model.selectableProfiles.map((p) => p.id), contains('qiniu'));
    expect(model.enabledProfiles.map((p) => p.id), isNot(contains('qiniu')));
    expect(model.activeProfile?.id, 'qiniu');
    expect(model.isConfigured, isFalse);
  });
}
