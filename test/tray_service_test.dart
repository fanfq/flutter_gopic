import 'package:flutter_gopic/services/tray_service.dart';
import 'package:flutter_gopic/services/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tray upload copies all successful URLs and reports partial failures',
    () async {
      final copied = <String>[];
      final iconUpdates = <({String icon, String? tooltip})>[];
      final recentUploads = <({String fileName, String url})>[];
      final service = TrayService(
        uploadFile: (file) async {
          if (file.path.endsWith('bad.png')) {
            throw UploadException('boom');
          }
          return UploadResult(
            'https://cdn.test/${file.uri.pathSegments.last}',
            '/bucket/key',
          );
        },
        clipboardWriter: copied.add,
        iconSetter: (icon, {tooltip}) async {
          iconUpdates.add((icon: icon, tooltip: tooltip));
        },
        recentUploadSetter: (fileName, url) async {
          recentUploads.add((fileName: fileName, url: url));
        },
        resetDelay: Duration.zero,
      );

      await service.processDroppedPaths([
        '/tmp/a.png',
        '/tmp/bad.png',
        '/tmp/c.jpg',
      ]);

      expect(copied, ['https://cdn.test/a.png\nhttps://cdn.test/c.jpg']);
      expect(iconUpdates.first.icon, 'done');
      expect(iconUpdates.first.tooltip, contains('已上传 2 张'));
      expect(iconUpdates.first.tooltip, contains('1 张失败'));
      expect(recentUploads.last, (
        fileName: 'c.jpg',
        url: 'https://cdn.test/c.jpg',
      ));
    },
  );

  test('tray upload ignores empty path lists', () async {
    final copied = <String>[];
    final iconUpdates = <({String icon, String? tooltip})>[];
    var uploads = 0;
    final service = TrayService(
      uploadFile: (file) async {
        uploads++;
        return UploadResult(
          'https://cdn.test/${file.uri.pathSegments.last}',
          '/bucket/key',
        );
      },
      clipboardWriter: copied.add,
      iconSetter: (icon, {tooltip}) async {
        iconUpdates.add((icon: icon, tooltip: tooltip));
      },
      resetDelay: Duration.zero,
    );

    await service.processDroppedPaths([]);

    expect(uploads, 0);
    expect(copied, isEmpty);
    expect(iconUpdates, isEmpty);
  });
}
