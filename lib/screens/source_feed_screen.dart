import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article.dart';
import '../models/source.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/rss_service.dart';
import '../widgets/article_card.dart';
import 'article_reader_screen.dart';

class SourceFeedScreen extends StatefulWidget {
  final Source source;
  const SourceFeedScreen({super.key, required this.source});

  @override
  State<SourceFeedScreen> createState() => _SourceFeedScreenState();
}

class _SourceFeedScreenState extends State<SourceFeedScreen> {
  final _rss = RssService();
  List<Article> _articles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feedProvider = context.read<FeedProvider>();
      final existing = feedProvider.allArticles
          .where((a) => a.sourceId == widget.source.id)
          .toList();
      if (existing.isNotEmpty) {
        setState(() {
          _articles = existing;
          _loading = false;
        });
      }
      _fetch();
    });
  }

  Future<void> _fetch() async {
    final fresh = await _rss.fetchFeed(widget.source);
    if (!mounted) return;

    if (fresh.isNotEmpty) {
      context.read<FeedProvider>().mergeSourceArticles(widget.source.id, fresh);
    }

    final allForSource = context
        .read<FeedProvider>()
        .allArticles
        .where((a) => a.sourceId == widget.source.id)
        .toList();

    if (mounted) {
      setState(() {
        _articles = allForSource;
        _loading = false;
      });
    }
  }

  void _openArticle(Article article) {
    final eink = context.read<SettingsProvider>().einkMode;
    if (eink) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleReaderScreen(article: article),
        ),
      );
    } else {
      launchUrl(Uri.parse(article.link), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<BookmarkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? const Center(child: Text('No articles found'))
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _articles.length,
                    itemBuilder: (context, i) {
                      final a = _articles[i];
                      return ArticleCard(
                        article: a,
                        isBookmarked: bookmarks.isBookmarked(a.id),
                        onBookmarkToggle: () => bookmarks.toggle(a),
                        onTap: () => _openArticle(a),
                      );
                    },
                  ),
                ),
    );
  }
}
