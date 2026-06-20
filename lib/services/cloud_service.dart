import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_model.dart';
import '../models/configuration_transfer.dart';

const _kCloudPrefKey = 'gopic_cloud';
const _kLegacyPrefKey = 'gopic_settings';

/// The outcome of appending imported configurations to local profiles.
class ConfigurationImportResult {
  const ConfigurationImportResult({required this.added});

  final int added;

  @override
  bool operator ==(Object other) =>
      other is ConfigurationImportResult && other.added == added;

  @override
  int get hashCode => added.hashCode;
}

/// Loads and persists [CloudModel] via shared_preferences.
class CloudService {
  CloudService() {
    model = CloudModel();
    _ready = _load();
  }

  late final CloudModel model;
  late final Future<void> _ready;

  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_kCloudPrefKey) ?? prefs.getString(_kLegacyPrefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          model.loadFromMap(decoded);
        }
      } catch (_) {
        // Corrupt store: ignore and keep defaults.
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCloudPrefKey, jsonEncode(model.toMap()));
  }

  Future<String> exportConfiguration() async {
    await ready;
    return ConfigurationTransfer.exportJson(model);
  }

  Future<ConfigurationImportResult> importConfiguration(String source) async {
    await ready;
    final result = ConfigurationTransfer.importJson(source, model);
    await save();
    return ConfigurationImportResult(added: result.added);
  }
}
