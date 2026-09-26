import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cloud_model.dart';

/// A single uploaded-image record shown in the gallery.
class HistoryItem {
  final String id;
  final String fileName;
  final String objectKey; // S3/R2 key
  final String url; // public URL returned to the user
  final int sizeBytes;
  final String contentType;
  final String? localThumbPath; // local cache of the uploaded file
  final DateTime uploadedAt;
  final String? cloudProfileId;
  final CloudProvider? cloudProvider;

  HistoryItem({
    required this.id,
    required this.fileName,
    required this.objectKey,
    required this.url,
    required this.sizeBytes,
    required this.contentType,
    required this.uploadedAt,
    this.localThumbPath,
    this.cloudProfileId,
    this.cloudProvider,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'fileName': fileName,
    'objectKey': objectKey,
    'url': url,
    'sizeBytes': sizeBytes,
    'contentType': contentType,
    'localThumbPath': localThumbPath,
    'uploadedAt': uploadedAt.toIso8601String(),
    'cloudProfileId': cloudProfileId,
    'cloudProvider': cloudProvider?.name,
  };

  factory HistoryItem.fromMap(Map<String, dynamic> m) => HistoryItem(
    id: m['id'] as String,
    fileName: m['fileName'] as String,
    objectKey: m['objectKey'] as String,
    url: m['url'] as String,
    sizeBytes: m['sizeBytes'] as int,
    contentType: m['contentType'] as String? ?? 'application/octet-stream',
    localThumbPath: m['localThumbPath'] as String?,
    uploadedAt: DateTime.parse(m['uploadedAt'] as String),
    cloudProfileId: m['cloudProfileId'] as String?,
    cloudProvider: m['cloudProvider'] is String
        ? CloudProvider.fromName(m['cloudProvider'] as String)
        : null,
  );
}

/// Observable list of uploaded items, newest first.
class HistoryModel extends ChangeNotifier {
  HistoryModel();

  final List<HistoryItem> _items = [];

  List<HistoryItem> get items => List.unmodifiable(_items);
  List<HistoryItem> itemsForProfile(String? profileId) {
    if (profileId == null || profileId.isEmpty) return const [];
    return _items
        .where((item) => item.cloudProfileId == profileId)
        .toList(growable: false);
  }

  /// Returns active-profile history filtered by a normalized extension. Empty
  /// extension means all files, which keeps the gallery default inclusive.
  List<HistoryItem> itemsForProfileAndExtension(
    String? profileId,
    String extension,
  ) {
    final items = itemsForProfile(profileId);
    final normalized = extension.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    if (normalized.isEmpty) return items;
    return items
        .where((item) => _extensionOf(item.fileName) == normalized)
        .toList(growable: false);
  }

  List<String> extensionsForProfile(String? profileId) =>
      itemsForProfile(profileId)
          .map((item) => _extensionOf(item.fileName))
          .where((extension) => extension.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  void loadFromJsonString(String json) {
    _items.clear();
    if (json.trim().isEmpty) {
      notifyListeners();
      return;
    }
    try {
      final list = jsonDecode(json) as List;
      _items.addAll(
        list.map((e) => HistoryItem.fromMap(e as Map<String, dynamic>)),
      );
      _items.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    } catch (_) {
      // Corrupt store: start clean.
    }
    notifyListeners();
  }

  String toJsonString() {
    final list = _items.map((e) => e.toMap()).toList();
    return jsonEncode(list);
  }

  void add(HistoryItem item) {
    _items.insert(0, item);
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void clearProfile(String profileId) {
    _items.removeWhere((e) => e.cloudProfileId == profileId);
    notifyListeners();
  }
}
