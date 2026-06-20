import 'dart:convert';

import 'package:flutter_gopic/models/cloud_model.dart';
import 'package:flutter_gopic/models/configuration_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CloudProfile profile({
    required String id,
    String name = 'Profile',
    CloudProvider provider = CloudProvider.cloudflareR2,
    bool isEnabled = true,
  }) => CloudProfile(
    id: id,
    provider: provider,
    name: name,
    isEnabled: isEnabled,
    accessKeyId: 'access-key',
    secretAccessKey: 'secret-key',
    bucket: 'bucket',
    endpoint: 'https://example.com',
  );

  test('exports versioned cloud configuration as UTC JSON', () {
    final model = CloudModel()
      ..loadFromMap({
        'activeProfileId': 'one',
        'profiles': [profile(id: 'one').toMap()],
        'compression': {'enabled': true, 'thresholdBytes': 20, 'quality': 80},
      });

    final exported = ConfigurationTransfer.exportJson(
      model,
      clock: () => DateTime.utc(2026, 6, 20, 10, 30),
    );
    final decoded = jsonDecode(exported) as Map<String, dynamic>;

    expect(decoded['version'], 1);
    expect(decoded['exportedAt'], '2026-06-20T10:30:00.000Z');
    expect(decoded['cloud'], model.toMap());
  });

  test('appends imported profiles without replacing local configuration', () {
    final existing = CloudModel()
      ..loadFromMap({
        'activeProfileId': 'existing',
        'profiles': [profile(id: 'existing', name: 'Old').toMap()],
        'compression': {'enabled': false, 'thresholdBytes': 1, 'quality': 20},
      });
    final source = jsonEncode({
      'version': 1,
      'exportedAt': '2026-06-20T10:30:00.000Z',
      'cloud': {
        'activeProfileId': 'added',
        'profiles': [
          profile(id: 'existing', name: 'Replacement').toMap(),
          profile(
            id: 'added',
            name: 'Added',
            provider: CloudProvider.awsS3,
          ).toMap(),
        ],
        'compression': {'enabled': true, 'thresholdBytes': 200, 'quality': 90},
      },
    });

    final result = ConfigurationTransfer.importJson(source, existing);

    expect(result.added, 2);
    expect(existing.profiles.firstWhere((p) => p.id == 'existing').name, 'Old');
    expect(existing.profiles.map((p) => p.id), contains('added'));
    expect(existing.profiles.any((p) => p.name == 'Replacement'), isTrue);
    expect(
      existing.profiles.map((p) => p.id).toSet().length,
      existing.profiles.length,
    );
    expect(existing.activeProfileId, 'existing');
    expect(existing.compression.toMap(), {
      'enabled': false,
      'thresholdBytes': 1,
      'quality': 20,
    });
  });

  test('keeps the current active id when imported active id is absent', () {
    final model = CloudModel()
      ..loadFromMap({
        'activeProfileId': 'existing',
        'profiles': [profile(id: 'existing').toMap()],
      });
    final source = jsonEncode({
      'version': 1,
      'exportedAt': '2026-06-20T10:30:00.000Z',
      'cloud': {
        'activeProfileId': 'missing',
        'profiles': [profile(id: 'added').toMap()],
        'compression': {'enabled': false, 'thresholdBytes': 1, 'quality': 70},
      },
    });

    ConfigurationTransfer.importJson(source, model);

    expect(model.activeProfileId, 'existing');
  });

  test('rejects invalid documents without changing the cloud model', () {
    final model = CloudModel()
      ..loadFromMap({
        'activeProfileId': 'existing',
        'profiles': [profile(id: 'existing', name: 'Original').toMap()],
      });
    final before = model.toMap();
    final malformedProfile = jsonEncode({
      'version': 1,
      'exportedAt': '2026-06-20T10:30:00.000Z',
      'cloud': {
        'profiles': [profile(id: '').toMap()],
        'activeProfileId': null,
        'compression': {'enabled': false, 'thresholdBytes': 1, 'quality': 70},
      },
    });

    expect(
      () => ConfigurationTransfer.importJson(malformedProfile, model),
      throwsFormatException,
    );
    expect(model.toMap(), before);
    expect(
      () => ConfigurationTransfer.importJson('{bad json', model),
      throwsFormatException,
    );
    expect(
      () => ConfigurationTransfer.importJson(
        jsonEncode({'version': 2, 'cloud': {}}),
        model,
      ),
      throwsFormatException,
    );
    expect(model.toMap(), before);
  });

  test(
    'rejects duplicate imported profile ids without changing the cloud model',
    () {
      final model = CloudModel()
        ..loadFromMap({
          'activeProfileId': 'existing',
          'profiles': [profile(id: 'existing', name: 'Original').toMap()],
          'compression': {'enabled': false, 'thresholdBytes': 1, 'quality': 20},
        });
      final before = model.toMap();
      final source = jsonEncode({
        'version': 1,
        'exportedAt': '2026-06-20T10:30:00.000Z',
        'cloud': {
          'activeProfileId': 'duplicate',
          'profiles': [
            profile(id: 'duplicate', name: 'First').toMap(),
            profile(id: 'duplicate', name: 'Second').toMap(),
          ],
          'compression': {
            'enabled': true,
            'thresholdBytes': 200,
            'quality': 90,
          },
        },
      });

      expect(
        () => ConfigurationTransfer.importJson(source, model),
        throwsFormatException,
      );
      expect(model.toMap(), before);
    },
  );
}
