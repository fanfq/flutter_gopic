import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_model.dart';

const _kPrefKey = 'gopic_history';

/// Persists the upload history index and caches uploaded files locally so the
/// gallery can show thumbnails even after the originals are moved or deleted.
class HistoryService {
  HistoryService() {
    model = HistoryModel();
    _load();
  }

  late final HistoryModel model;

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
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'gopic_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
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
