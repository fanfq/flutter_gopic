import 'package:flutter_gopic/services/upload_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports byte fraction and rolling upload rate', () {
    var now = DateTime(2026, 9, 26, 12);
    final tracker = UploadProgressTracker(clock: () => now);

    tracker.addBytes(1024 * 1024);
    now = now.add(const Duration(seconds: 1));
    final progress = tracker.snapshot(totalBytes: 2 * 1024 * 1024);

    expect(progress.fraction, .5);
    expect(progress.bytesPerSecond, 1024 * 1024);
  });

  test(
    'does not publish a rate from an unrealistically short sample window',
    () {
      var now = DateTime(2026, 9, 26, 12);
      final tracker = UploadProgressTracker(clock: () => now);

      tracker.addBytes(1024 * 1024 * 1024);
      now = now.add(const Duration(milliseconds: 1));

      expect(
        tracker.snapshot(totalBytes: 1024 * 1024 * 1024).bytesPerSecond,
        0,
      );
    },
  );
}
