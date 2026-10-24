import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';
import '../models/source.dart';
import '../services/article_cache_service.dart';
import '../services/rss_service.dart';

enum FeedViewMode { latest, perSource }

class FeedProvider extends ChangeNotifier {
  List<Article> _allSavedArticles = [];
  List<Article> _chronoArticles = [];
  List<Article> _perSourceArticles = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastRefresh;
  int _sourceCount = 0;
  FeedViewMode _viewMode = FeedViewMode.latest;
  Set<String> _activeSourceIds = {};
  String? _selectedCategory;

  final RssService _rssService = RssService();
  final ArticleCacheService _cacheService = ArticleCacheService();

  List<Article> get allArticles =>
      _viewMode == FeedViewMode.latest ? _chronoArticles : _perSourceArticles;

  List<Article> get articles {
    final list = allArticles;
    if (_selectedCategory == null ||
        _selectedCategory!.isEmpty ||
        _selectedCategory == 'All') {
      return list;
    }
    return list
        .where((a) =>
            a.category.trim().toLowerCase() ==
            _selectedCategory!.trim().toLowerCase())
        .toList();
  }

  String? get selectedCategory => _selectedCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastRefresh => _lastRefresh;
  int get sourceCount => _sourceCount;
  FeedViewMode get viewMode => _viewMode;

  int get filteredSourceCount {
    if (_selectedCategory == null ||
        _selectedCategory!.isEmpty ||
        _selectedCategory == 'All') {
      return _sourceCount;
    }
    return articles.map((a) => a.sourceId).toSet().length;
  }

  /// Source IDs that returned at least one article on last fetch.
  Set<String> get activeSourceIds => _activeSourceIds;

  Future<void> initCache() async {
    _allSavedArticles = await _cacheService.loadCachedArticles();
    if (_allSavedArticles.isNotEmpty) {
      _rebuildViews();
      _activeSourceIds = _allSavedArticles.map((a) => a.sourceId).toSet();
      notifyListeners();
    }
  }

  void selectCategory(String? category) {
    if (category == 'All' || category == null || category.isEmpty) {
      _selectedCategory = null;
    } else {
      _selectedCategory = category;
    }
    notifyListeners();
  }

  void updateSourceCategory(String sourceId, String newCategory) {
    for (final a in _allSavedArticles) {
      if (a.sourceId == sourceId) {
        a.category = newCategory;
      }
    }
    for (final a in _chronoArticles) {
      if (a.sourceId == sourceId) {
        a.category = newCategory;
      }
    }
    for (final a in _perSourceArticles) {
      if (a.sourceId == sourceId) {
        a.category = newCategory;
      }
    }
    _cacheService.saveCachedArticles(_allSavedArticles);
    notifyListeners();
  }

  void toggleViewMode() {
    _viewMode = _viewMode == FeedViewMode.latest
        ? FeedViewMode.perSource
        : FeedViewMode.latest;
    notifyListeners();
  }

  Future<void> refresh(List<Source> activeSources) async {
    _isLoading = true;
    _error = null;
    _sourceCount = activeSources.length;
    notifyListeners();

    try {
      final freshResults = await _rssService.fetchAllFeeds(activeSources);

      // Track active sources that returned items
      final returnedSourceIds = freshResults.map((a) => a.sourceId).toSet();
      _activeSourceIds.addAll(returnedSourceIds);

      // Merge fresh articles with existing saved articles (additive, persistent)
      final existingMap = <String, Article>{};
      for (final a in _allSavedArticles) {
        existingMap[a.id] = a;
      }

      // Add or update with fresh articles
      for (final fresh in freshResults) {
        existingMap[fresh.id] = fresh;
      }

      // Keep only articles belonging to current sources (remove if source was deleted)
      final activeIds = activeSources.map((s) => s.id).toSet();
      final mergedList = existingMap.values
          .where((a) => activeIds.contains(a.sourceId))
          .toList();

      // Sort by publication date descending
      mergedList.sort((a, b) {
        if (a.publishedAt == null) return 1;
        if (b.publishedAt == null) return -1;
        return b.publishedAt!.compareTo(a.publishedAt!);
      });

      // Keep up to 500 articles to avoid unbounded memory / storage usage
      _allSavedArticles = mergedList.take(500).toList();
      _rebuildViews();

      _lastRefresh = DateTime.now();
      await _cacheService.saveCachedArticles(_allSavedArticles);
      _updateHomeWidget(_chronoArticles);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Merge articles fetched specifically for a single source (used by SourceFeedScreen)
  void mergeSourceArticles(String sourceId, List<Article> freshArticles) {
    if (freshArticles.isEmpty) return;

    final existingMap = <String, Article>{};
    for (final a in _allSavedArticles) {
      existingMap[a.id] = a;
    }

    for (final fresh in freshArticles) {
      existingMap[fresh.id] = fresh;
    }

    final mergedList = existingMap.values.toList();
    mergedList.sort((a, b) {
      if (a.publishedAt == null) return 1;
      if (b.publishedAt == null) return -1;
      return b.publishedAt!.compareTo(a.publishedAt!);
    });

    _allSavedArticles = mergedList.take(500).toList();
    _activeSourceIds.add(sourceId);
    _rebuildViews();
    _cacheService.saveCachedArticles(_allSavedArticles);
    notifyListeners();
  }

  void _rebuildViews() {
    _chronoArticles = _spreadSources(List.of(_allSavedArticles));
    _perSourceArticles = _buildPerSourceView(_allSavedArticles);
  }

  static const _widgetChannel =
      MethodChannel('com.pluralis.pluralis/widget');

  /// Push latest articles to the Android home screen widget.
  Future<void> _updateHomeWidget(List<Article> articles) async {
    try {
      final top = articles.take(10).map((a) => {
            'title': a.title,
            'description': a.description ?? '',
            'link': a.link,
            'sourceName': a.sourceName,
          }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_articles', jsonEncode(top));
      await _widgetChannel.invokeMethod('updateWidget');
    } catch (_) {
      // Widget update is best-effort
    }
  }

  /// Round-robin: 1 article per source, cycling through all sources.
  /// Sources ranked by most recent article.
  static List<Article> _buildPerSourceView(List<Article> sorted) {
    final bySource = <String, List<Article>>{};
    for (final a in sorted) {
      bySource.putIfAbsent(a.sourceId, () => []).add(a);
    }

    final sourceOrder = bySource.keys.toList();
    sourceOrder.sort((a, b) {
      final aFirst = bySource[a]!.first.publishedAt;
      final bFirst = bySource[b]!.first.publishedAt;
      if (aFirst == null) return 1;
      if (bFirst == null) return -1;
      return bFirst.compareTo(aFirst);
    });

    final result = <Article>[];
    int round = 0;
    bool added = true;

    while (added) {
      added = false;
      for (final sourceId in sourceOrder) {
        final list = bySource[sourceId]!;
        if (round < list.length) {
          result.add(list[round]);
          added = true;
        }
      }
      round++;
    }

    return result;
  }

  /// Breaks up blocks of 3+ consecutive articles from the same source.
  static List<Article> _spreadSources(List<Article> sorted) {
    const maxConsecutive = 2;
    final result = <Article>[];
    final deferred = <Article>[];

    String? lastSourceId;
    int consecutive = 0;

    for (final article in sorted) {
      if (article.sourceId == lastSourceId) {
        consecutive++;
      } else {
        lastSourceId = article.sourceId;
        consecutive = 1;
      }

      if (consecutive > maxConsecutive) {
        deferred.add(article);
      } else {
        if (deferred.isNotEmpty) {
          final idx =
              deferred.indexWhere((d) => d.sourceId != article.sourceId);
          if (idx >= 0) {
            result.add(deferred.removeAt(idx));
          }
        }
        result.add(article);
      }
    }

    result.addAll(deferred);
    return result;
  }
}
