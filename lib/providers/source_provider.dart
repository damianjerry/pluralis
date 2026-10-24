import 'package:flutter/foundation.dart';
import '../models/source.dart';
import '../services/source_service.dart';

class SourceProvider extends ChangeNotifier {
  List<Source> _sources = [];
  List<String> _categories = [];

  List<Source> get sources => _sources;
  List<Source> get activeSources => _sources.where((s) => s.active).toList();
  List<String> get categories => _categories;

  final SourceService _service = SourceService();

  Future<void> load() async {
    _sources = await _service.loadSources();
    _categories = await _service.loadCategories();
    notifyListeners();
  }

  Future<void> toggleSource(String id) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _sources[i].active = !_sources[i].active;
      await _service.saveSources(_sources);
      notifyListeners();
    }
  }

  Future<void> addSource(Source source) async {
    await _service.addCustomSource(source);
    await load();
  }

  Future<void> removeSource(String id) async {
    await _service.removeSource(id);
    await load();
  }

  Future<void> updateSourceCategory(String id, String newCategory) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _sources[i].category = newCategory;
      await _service.saveSources(_sources);
      notifyListeners();
    }
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_categories.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    _categories.add(trimmed);
    await _service.saveCategories(_categories);
    notifyListeners();
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final index =
        _categories.indexWhere((c) => c.toLowerCase() == oldName.toLowerCase());
    if (index >= 0) {
      _categories[index] = trimmed;
      for (final s in _sources) {
        if (s.category.toLowerCase() == oldName.toLowerCase()) {
          s.category = trimmed;
        }
      }
      await _service.saveCategories(_categories);
      await _service.saveSources(_sources);
      notifyListeners();
    }
  }

  Future<void> deleteCategory(String name) async {
    _categories.removeWhere((c) => c.toLowerCase() == name.toLowerCase());
    for (final s in _sources) {
      if (s.category.toLowerCase() == name.toLowerCase()) {
        s.category = 'custom';
      }
    }
    await _service.saveCategories(_categories);
    await _service.saveSources(_sources);
    notifyListeners();
  }

  Future<void> updateSourceCookie(String id, String? cookie) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _sources[i].cookie = cookie;
      await _service.saveSources(_sources);
      notifyListeners();
    }
  }

  /// Add multiple sources at once (used by OPML/CSV import)
  Future<void> addSources(List<Source> newSources) async {
    final existingIds = _sources.map((s) => s.id).toSet();
    final toAdd = newSources.where((s) => !existingIds.contains(s.id)).toList();
    if (toAdd.isEmpty) return;
    for (final s in toAdd) {
      await _service.addCustomSource(s);
    }
    await load();
  }
}
