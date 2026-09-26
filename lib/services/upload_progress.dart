/// Immutable progress reported by upload transports.
class UploadProgress {
  const UploadProgress({
    required this.sentBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final int sentBytes;
  final int totalBytes;
  final int bytesPerSecond;

  double get fraction => totalBytes == 0 ? 0 : sentBytes / totalBytes;
}

/// Calculates a transfer rate from byte deltas without coupling it to a cloud
/// provider. Uploaders call [addBytes] only after bytes have been accepted by
/// the socket, keeping displayed progress monotonic.
class UploadProgressTracker {
  /// Shorter windows measure socket buffering rather than network throughput.
  static const _minimumSampleWindow = Duration(milliseconds: 250);
  UploadProgressTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _lastSampleAt = _clock();
  }

  final DateTime Function() _clock;
  late DateTime _lastSampleAt;
  var _sentBytes = 0;
  var _lastSampleBytes = 0;
  var _bytesPerSecond = 0;

  void addBytes(int count) {
    if (count <= 0) return;
    _sentBytes += count;
  }

  UploadProgress snapshot({required int totalBytes}) {
    final now = _clock();
    final elapsedMicros = now.difference(_lastSampleAt).inMicroseconds;
    if (elapsedMicros >= _minimumSampleWindow.inMicroseconds) {
      _bytesPerSecond =
          ((_sentBytes - _lastSampleBytes) *
                  Duration.microsecondsPerSecond /
                  elapsedMicros)
              .round();
      _lastSampleAt = now;
      _lastSampleBytes = _sentBytes;
    }
    return UploadProgress(
      sentBytes: _sentBytes,
      totalBytes: totalBytes,
      bytesPerSecond: _bytesPerSecond,
    );
  }
}
