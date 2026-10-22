// Settings keys used by the intelligence module and their defaults.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/app_db.dart';

class IntelKeys {
  static const memoryEnabled = 'memory_enabled';
  static const memoryAutoExtract = 'memory_auto_extract';
  static const memoryEmbeddingModel = 'memory_embedding_model'; // providerId::modelId, empty = off
  static const autoCompact = 'auto_compact_enabled';
  static const autoCompactThreshold = 'auto_compact_threshold';
  static const fallbackWindow = 'context_fallback_window';
  static const execMode = 'tools_exec_mode';
  static const toolsDisabled = 'tools_disabled'; // JSON list of built-in tool names
  static const toolResultMax = 'tool_result_max_chars';
  // Renamed whenever built-in skills are added, so existing installs seed the new ones too.
  static const skillsSeeded = 'skills_builtin_seeded_v3';
}

extension IntelSettingsX on AppDb {
  Future<bool> boolSetting(String key, {bool def = true}) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return def;
    return v == 'true' || v == '1';
  }

  Future<double> doubleSetting(String key, double def) async => double.tryParse(await getSetting(key) ?? '') ?? def;
  Future<int> intSetting(String key, int def) async => int.tryParse(await getSetting(key) ?? '') ?? def;

  Future<Set<String>> stringSetSetting(String key) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return {};
    try {
      return (jsonDecode(v) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> setStringSet(String key, Set<String> v) => setSetting(key, jsonEncode(v.toList()..sort()));
}

/// Watches a boolean setting with a default (for switches in the UI).
final boolSettingProvider = StreamProvider.autoDispose.family<bool, (String, bool)>((ref, a) =>
    ref.watch(dbProvider).watchSetting(a.$1).map((v) => v == null || v.isEmpty ? a.$2 : (v == 'true' || v == '1')));

final stringSettingProvider =
    StreamProvider.autoDispose.family<String?, String>((ref, key) => ref.watch(dbProvider).watchSetting(key));
