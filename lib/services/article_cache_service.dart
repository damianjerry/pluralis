import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/article.dart';

class ArticleCacheService {
  static const _cacheFileName = 'pluralis_articles_cache.json';

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<List<Article>> loadCachedArticles() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return [];
        final list = json.decode(content) as List<dynamic>;
        return list
            .map((j) => Article.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveCachedArticles(List<Article> articles) async {
    try {
      final file = await _getCacheFile();
      // Keep up to 500 latest articles to avoid filling disk space
      final toSave = articles.take(500).map((a) => a.toJson()).toList();
      await file.writeAsString(json.encode(toSave));
    } catch (_) {}
  }
}
