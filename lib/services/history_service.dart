import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_model.dart';

const _kPrefKey = 'gopic_history';

class CacheSummary {
  const CacheSummary({
    required this.directoryPath,
    required this.fileCount,
    required this.totalBytes,
  });

  final String directoryPath;
  final int fileCount;
  final int totalBytes;

  @override
  bool operator ==(Object other) =>
      other is CacheSummary &&
      other.directoryPath == directoryPath &&
      other.fileCount == fileCount &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(directoryPath, fileCount, totalBytes);
}

class CacheExportResult {
  const CacheExportResult({required this.exported, required this.failed});
  final int exported;
  final int failed;
}

/// Persists the upload history index and caches uploaded files locally so the
/// gallery can show thumbnails even after the originals are moved or deleted.
class HistoryService {
  HistoryService({Future<Directory> Function()? cacheDirectoryResolver})
    : _cacheDirectoryResolver = cacheDirectoryResolver {
    model = HistoryModel();
    _ready = _load();
  }

  late final HistoryModel model;
  final Future<Directory> Function()? _cacheDirectoryResolver;
  late final Future<void> _ready;

  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    model.loadFromJsonString(prefs.getString(_kPrefKey) ?? '');
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, model.toJsonString());
  }

  /// Directory where uploaded files are mirrored for local thumbnails.
  Future<Directory> cacheDir() async {
    final dir = _cacheDirectoryResolver != null
        ? await _cacheDirectoryResolver()
        : Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'gopic_cache',
            ),
          );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<CacheSummary> cacheSummary() async {
    final dir = await cacheDir();
    var fileCount = 0;
    var totalBytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        fileCount++;
        totalBytes += await entity.length();
      }
    }
    return CacheSummary(
      directoryPath: dir.path,
      fileCount: fileCount,
      totalBytes: totalBytes,
    );
  }

  /// Deletes only local thumbnail files; upload history is preserved.
  Future<void> clearCache() async {
    final dir = await cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  /// Copy the source file into the local cache and return the path.
  Future<String> cacheFile(String sourcePath, String fileName) async {
    final dir = await cacheDir();
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final target = File(
      p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_$safeName'),
    );
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<void> add(HistoryItem item) async {
    model.add(item);
    await save();
  }

  /// Copies selected cached originals to [destination] without touching remote
  /// cloud objects or removing their upload history.
  Future<CacheExportResult> exportCachedFiles({
    required Set<String> ids,
    required Directory destination,
  }) async {
    var exported = 0;
    var failed = 0;
    for (final item in model.items.where((item) => ids.contains(item.id))) {
      final sourcePath = item.localThumbPath;
      if (sourcePath == null || !await File(sourcePath).exists()) {
        failed++;
        continue;
      }
      try {
        final source = File(sourcePath);
        var target = File(p.join(destination.path, item.fileName));
        var copyIndex = 1;
        while (await target.exists()) {
          final ext = p.extension(item.fileName);
          final base = p.basenameWithoutExtension(item.fileName);
          target = File(p.join(destination.path, '$base ($copyIndex)$ext'));
          copyIndex++;
        }
        await source.copy(target.path);
        exported++;
      } catch (_) {
        failed++;
      }
    }
    return CacheExportResult(exported: exported, failed: failed);
  }

  Future<void> removeMany(Set<String> ids) async {
    for (final id in ids.toList()) {
      if (model.items.any((item) => item.id == id)) await remove(id);
    }
  }

  Future<void> remove(String id, {bool deleteCache = true}) async {
    final item = model.items.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StateError('not found'),
    );
    if (deleteCache && item.localThumbPath != null) {
      final f = File(item.localThumbPath!);
      if (f.existsSync()) f.deleteSync();
    }
    model.remove(id);
    await save();
  }

  Future<void> clear({bool deleteCache = true}) async {
    if (deleteCache) {
      final dir = await cacheDir();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        dir.createSync(recursive: true);
      }
    }
    model.clear();
    await save();
  }

  Future<void> clearProfile(String profileId, {bool deleteCache = true}) async {
    if (deleteCache) {
      final items = model.itemsForProfile(profileId);
      for (final item in items) {
        final path = item.localThumbPath;
        if (path == null) continue;
        final file = File(path);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {
            // Cache cleanup is best effort.
          }
        }
      }
    }
    model.clearProfile(profileId);
    await save();
  }
}
