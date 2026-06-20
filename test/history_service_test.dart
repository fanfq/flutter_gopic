import 'dart:io';

import 'package:flutter_gopic/models/history_model.dart';
import 'package:flutter_gopic/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('gopic-cache-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'reports and clears cache files without deleting upload history',
    () async {
      final service = HistoryService(
        cacheDirectoryResolver: () async => tempDir,
      );
      await service.ready;
      await File(p.join(tempDir.path, 'one.png')).writeAsBytes([1, 2]);
      await Directory(p.join(tempDir.path, 'nested')).create();
      await File(
        p.join(tempDir.path, 'nested', 'two.jpg'),
      ).writeAsBytes([3, 4, 5]);
      service.model.add(
        HistoryItem(
          id: 'item',
          fileName: 'one.png',
          objectKey: '/bucket/one.png',
          url: 'https://cdn.example.com/one.png',
          sizeBytes: 2,
          contentType: 'image/png',
          uploadedAt: DateTime(2026, 6, 20),
        ),
      );

      expect(
        await service.cacheSummary(),
        CacheSummary(directoryPath: tempDir.path, fileCount: 2, totalBytes: 5),
      );

      await service.clearCache();

      expect(
        await service.cacheSummary(),
        CacheSummary(directoryPath: tempDir.path, fileCount: 0, totalBytes: 0),
      );
      expect(service.model.items, hasLength(1));
    },
  );
}
