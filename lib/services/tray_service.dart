import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../services/upload_service.dart';

typedef TrayUploadFile = Future<UploadResult> Function(File file);
typedef TrayClipboardWriter = FutureOr<void> Function(String text);
typedef TrayIconSetter =
    FutureOr<void> Function(String icon, {String? tooltip});
typedef TrayRecentUploadSetter =
    FutureOr<void> Function(String fileName, String url);

/// Bridges the macOS menu-bar item (created in Swift) with Dart.
///
/// The native `StatusBarController` forwards dropped file paths over the
/// `gopic/tray` channel. This service uploads each file via [UploadService],
/// copies the resulting URL to the clipboard, and updates the status-bar icon
/// (uploading → done / error) by calling back into Swift.
class TrayService {
  TrayService({
    this.uploadService,
    TrayUploadFile? uploadFile,
    TrayClipboardWriter? clipboardWriter,
    TrayIconSetter? iconSetter,
    TrayRecentUploadSetter? recentUploadSetter,
    this.resetDelay = const Duration(seconds: 3),
  }) : _uploadFile = uploadFile,
       _clipboardWriter = clipboardWriter,
       _iconSetter = iconSetter,
       _recentUploadSetter = recentUploadSetter {
    assert(uploadService != null || uploadFile != null);
  }

  final UploadService? uploadService;
  final TrayUploadFile? _uploadFile;
  final TrayClipboardWriter? _clipboardWriter;
  final TrayIconSetter? _iconSetter;
  final TrayRecentUploadSetter? _recentUploadSetter;
  final Duration resetDelay;
  static const _channel = MethodChannel('gopic/tray');
  bool _started = false;

  /// Start listening for files dropped onto the menu-bar icon. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_handle);
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onFilesDropped' && call.arguments is String) {
      final paths = (call.arguments as String)
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (paths.isNotEmpty) {
        // Don't await on the channel handler: we want to return to Swift
        // immediately while uploads proceed in the background.
        processDroppedPaths(paths);
      }
    }
    return null;
  }

  Future<void> processDroppedPaths(List<String> paths) async {
    if (paths.isEmpty) return;

    var success = 0;
    var failed = 0;
    final urls = <String>[];

    for (final path in paths) {
      try {
        final result = await _upload(File(path));
        urls.add(result.url);
        await setLatestUpload(_fileName(path), result.url);
        success++;
      } catch (_) {
        failed++;
      }
    }

    if (success > 0 && urls.isNotEmpty) {
      await _writeClipboard(urls.join('\n'));
      _setIcon(
        'done',
        tooltip:
            '已上传 $success 张，链接已复制'
            '${failed > 0 ? "（$failed 张失败）" : ""}',
      );
    } else {
      _setIcon('error', tooltip: '上传失败（$failed 张）');
    }

    // Return to idle after a short pause.
    if (resetDelay == Duration.zero) {
      return;
    }
    Future.delayed(resetDelay, () => _setIcon('cloud'));
  }

  Future<UploadResult> _upload(File file) {
    final injected = _uploadFile;
    if (injected != null) return injected(file);
    return uploadService!.uploadFile(file);
  }

  Future<void> _writeClipboard(String text) async {
    final injected = _clipboardWriter;
    if (injected != null) {
      await injected(text);
      return;
    }
    return Clipboard.setData(ClipboardData(text: text));
  }

  void _setIcon(String icon, {String? tooltip}) {
    final injected = _iconSetter;
    if (injected != null) {
      injected(icon, tooltip: tooltip);
      return;
    }
    try {
      if (tooltip != null) {
        _channel.invokeMethod('setIconAndTooltip', {
          'icon': icon,
          'tooltip': tooltip,
        });
      } else {
        _channel.invokeMethod('setIcon', icon);
      }
    } on PlatformException {
      // Channel may not be ready yet (e.g. running on non-macOS). Ignore.
    } catch (_) {
      // ignore
    }
  }

  Future<void> setLatestUpload(String fileName, String url) async {
    final injected = _recentUploadSetter;
    if (injected != null) {
      await injected(fileName, url);
      return;
    }
    try {
      await _channel.invokeMethod('setLatestUpload', {
        'fileName': fileName,
        'url': url,
      });
    } on PlatformException {
      // Channel may not be ready yet (e.g. running on non-macOS). Ignore.
    } catch (_) {
      // ignore
    }
  }

  String _fileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}
