import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings_model.dart';

const _kPrefKey = 'gopic_settings';

/// Loads and persists [SettingsModel] via shared_preferences.
class SettingsService {
  SettingsService() {
    model = SettingsModel();
    _load();
  }

  late final SettingsModel model;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefKey);
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
    await prefs.setString(_kPrefKey, jsonEncode(model.toMap()));
  }
}
