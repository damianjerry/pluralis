import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source.dart';

class SourceService {
  static const _sourcesKey = 'sources_state';
  static const _customSourcesKey = 'custom_sources';
  static const _removedDefaultsKey = 'removed_default_sources';
  static const _categoriesKey = 'user_categories';
  static const _sourceCategoryOverridesKey = 'source_category_overrides';

  Future<List<String>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_categoriesKey) ?? ['Știri', 'Analize'];
  }

  Future<void> saveCategories(List<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoriesKey, categories);
  }

  Future<List<Source>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();

    // Load removed default IDs
    final removedDefaults =
        (prefs.getStringList(_removedDefaultsKey) ?? []).toSet();

    // Load category overrides (for default sources)
    final overridesStr = prefs.getString(_sourceCategoryOverridesKey);
    final overrides = overridesStr != null
        ? Map<String, dynamic>.from(json.decode(overridesStr) as Map)
        : <String, dynamic>{};

    // Load defaults from asset, filtering out removed ones
    final jsonStr = await rootBundle.loadString('assets/sources.json');
    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    final defaults = jsonList
        .map((j) =>
            Source.fromJson(j as Map<String, dynamic>, isDefault: true))
        .where((s) => !removedDefaults.contains(s.id))
        .toList();

    for (final s in defaults) {
      if (overrides.containsKey(s.id)) {
        s.category = overrides[s.id] as String;
      }
    }

    // Load saved active/inactive state
    final stateStr = prefs.getString(_sourcesKey);
    if (stateStr != null) {
      final Map<String, dynamic> stateMap =
          json.decode(stateStr) as Map<String, dynamic>;
      for (final source in defaults) {
        if (stateMap.containsKey(source.id)) {
          source.active = stateMap[source.id] as bool;
        }
      }
    }

    // Load custom sources
    final customStr = prefs.getString(_customSourcesKey);
    if (customStr != null) {
      final List<dynamic> customList = json.decode(customStr) as List<dynamic>;
      for (final j in customList) {
        defaults.add(
            Source.fromJson(j as Map<String, dynamic>, isDefault: false));
      }
    }

    return defaults;
  }

  Future<void> saveSources(List<Source> sources) async {
    final prefs = await SharedPreferences.getInstance();

    // Save active/inactive state as map {id: bool}
    final stateMap = <String, bool>{};
    for (final s in sources) {
      stateMap[s.id] = s.active;
    }
    await prefs.setString(_sourcesKey, json.encode(stateMap));

    // Save custom sources separately
    final customSources =
        sources.where((s) => !s.isDefault).map((s) => s.toJson()).toList();
    await prefs.setString(_customSourcesKey, json.encode(customSources));

    // Save category overrides for default sources
    final defaultOverrides = <String, String>{};
    for (final s in sources.where((s) => s.isDefault)) {
      defaultOverrides[s.id] = s.category;
    }
    await prefs.setString(
        _sourceCategoryOverridesKey, json.encode(defaultOverrides));
  }

  Future<void> addCustomSource(Source source) async {
    final sources = await loadSources();
    sources.add(source);
    await saveSources(sources);
  }

  Future<void> removeSource(String id) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if this is a default source by looking at the asset
    final jsonStr = await rootBundle.loadString('assets/sources.json');
    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    final isDefault =
        jsonList.any((j) => (j as Map<String, dynamic>)['id'] == id);

    if (isDefault) {
      // Track removed default source
      final removed = prefs.getStringList(_removedDefaultsKey) ?? [];
      if (!removed.contains(id)) {
        removed.add(id);
        await prefs.setStringList(_removedDefaultsKey, removed);
      }
    }

    // Reload (now filtered) and save
    final sources = await loadSources();
    sources.removeWhere((s) => s.id == id);
    await saveSources(sources);
  }
}
