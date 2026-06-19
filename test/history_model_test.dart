import 'package:flutter_gopic/models/history_model.dart';
import 'package:flutter_gopic/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters gallery items by active cloud profile', () {
    final now = DateTime(2026, 6, 16);
    final history = HistoryModel()
      ..add(
        HistoryItem(
          id: 'r2-item',
          fileName: 'r2.png',
          objectKey: '/bucket/r2.png',
          url: 'https://r2.test/r2.png',
          sizeBytes: 10,
          contentType: 'image/png',
          uploadedAt: now,
          cloudProfileId: 'r2',
          cloudProvider: CloudProvider.cloudflareR2,
        ),
      )
      ..add(
        HistoryItem(
          id: 'aws-item',
          fileName: 'aws.png',
          objectKey: '/bucket/aws.png',
          url: 'https://aws.test/aws.png',
          sizeBytes: 10,
          contentType: 'image/png',
          uploadedAt: now,
          cloudProfileId: 'aws',
          cloudProvider: CloudProvider.awsS3,
        ),
      )
      ..add(
        HistoryItem(
          id: 'legacy-item',
          fileName: 'legacy.png',
          objectKey: '/bucket/legacy.png',
          url: 'https://legacy.test/legacy.png',
          sizeBytes: 10,
          contentType: 'image/png',
          uploadedAt: now,
        ),
      );

    expect(history.itemsForProfile('r2').map((e) => e.id), ['r2-item']);
    expect(history.itemsForProfile('aws').map((e) => e.id), ['aws-item']);
    expect(history.itemsForProfile(null), isEmpty);
  });
}
