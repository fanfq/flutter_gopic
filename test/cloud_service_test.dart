import 'dart:convert';

import 'package:flutter_gopic/models/cloud_model.dart';
import 'package:flutter_gopic/models/configuration_transfer.dart';
import 'package:flutter_gopic/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'loads the legacy cloud data and writes the Cloud preference key',
    () async {
      const profile = CloudProfile(
        id: 'legacy-r2',
        provider: CloudProvider.cloudflareR2,
        name: 'Legacy R2',
        isEnabled: true,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://r2.example.com',
      );
      SharedPreferences.setMockInitialValues({
        'gopic_settings': jsonEncode({
          'profiles': [profile.toMap()],
          'activeProfileId': profile.id,
        }),
      });

      final service = CloudService();
      await service.ready;

      expect(service.model.activeProfile?.id, profile.id);

      await service.save();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('gopic_cloud'), isNotNull);
    },
  );

  test(
    'exports and imports configuration through persisted cloud storage',
    () async {
      final original = CloudProfile(
        id: 'original',
        provider: CloudProvider.cloudflareR2,
        name: 'Original',
        isEnabled: true,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://r2.example.com',
      );
      final importedCopy = original.copyWith(name: 'Imported copy');
      final added = CloudProfile(
        id: 'added',
        provider: CloudProvider.awsS3,
        name: 'Added',
        isEnabled: true,
        accessKeyId: 'new-ak',
        secretAccessKey: 'new-sk',
        bucket: 'new-bucket',
        endpoint: 'https://s3.example.com',
      );
      SharedPreferences.setMockInitialValues({
        'gopic_cloud': jsonEncode({
          'profiles': [original.toMap()],
          'activeProfileId': original.id,
          'compression': const CompressionConfig().toMap(),
        }),
      });
      final service = CloudService();
      await service.ready;
      final source = jsonEncode({
        'version': ConfigurationTransfer.supportedVersion,
        'exportedAt': '2026-06-20T00:00:00.000Z',
        'cloud': {
          'profiles': [importedCopy.toMap(), added.toMap()],
          'activeProfileId': added.id,
          'compression': const CompressionConfig(enabled: true).toMap(),
        },
      });

      final beforeImport = service.model.toMap();
      final exported =
          jsonDecode(await service.exportConfiguration())
              as Map<String, dynamic>;
      final result = await service.importConfiguration(source);
      final preferences = await SharedPreferences.getInstance();

      expect(exported['version'], ConfigurationTransfer.supportedVersion);
      expect(exported['cloud'], beforeImport);
      expect(result.added, 2);
      final preserved = service.model.profiles.firstWhere(
        (profile) => profile.id == original.id,
      );
      expect(preserved.name, original.name);
      expect(preserved.accessKeyId, original.accessKeyId);
      expect(
        service.model.profiles.any(
          (profile) => profile.name == importedCopy.name,
        ),
        isTrue,
      );
      expect(service.model.activeProfileId, original.id);
      expect(
        service.model.compression.toMap(),
        const CompressionConfig().toMap(),
      );
      expect(
        jsonDecode(preferences.getString('gopic_cloud')!),
        service.model.toMap(),
      );
    },
  );

  test(
    'does not mutate or persist when configuration import is invalid',
    () async {
      const original = CloudProfile(
        id: 'original',
        provider: CloudProvider.cloudflareR2,
        name: 'Original',
        isEnabled: true,
        accessKeyId: 'ak',
        secretAccessKey: 'sk',
        bucket: 'bucket',
        endpoint: 'https://r2.example.com',
      );
      final initial = {
        'profiles': [original.toMap()],
        'activeProfileId': original.id,
        'compression': const CompressionConfig().toMap(),
      };
      SharedPreferences.setMockInitialValues({
        'gopic_cloud': jsonEncode(initial),
      });
      final service = CloudService();
      await service.ready;
      final before = service.model.toMap();

      await expectLater(
        service.importConfiguration('{not valid json'),
        throwsFormatException,
      );
      final preferences = await SharedPreferences.getInstance();

      expect(service.model.toMap(), before);
      expect(jsonDecode(preferences.getString('gopic_cloud')!), initial);
    },
  );
}
