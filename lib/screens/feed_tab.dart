import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/feed_provider.dart';
import '../providers/source_provider.dart';
import '../providers/bookmark_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/article_card.dart';
import '../widgets/font_size_controls.dart';
import 'article_reader_screen.dart';

class FeedTab extends StatelessWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final bookmarks = context.watch<BookmarkProvider>();
    final settings = context.watch<SettingsProvider>();
    final sourceProvider = context.watch<SourceProvider>();

    final selectedCat = feed.selectedCategory;
    final subtitle = selectedCat != null
        ? '${feed.articles.length} articles · $selectedCat'
        : '${feed.articles.length} articles from ${feed.sourceCount} sources';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pluralis'),
            if (feed.articles.isNotEmpty)
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          // E-ink toggle
          IconButton(
            icon: Icon(
              settings.einkMode ? Icons.menu_book : Icons.menu_book_outlined,
              color: settings.einkMode ? const Color(0xFFE8A020) : null,
            ),
            tooltip: settings.einkMode ? 'E-ink mode ON' : 'E-ink mode OFF',
            onPressed: () => settings.toggleEinkMode(),
          ),
          const FontSizeControls(),
          const SizedBox(width: 4),
          // View mode toggle
          TextButton.icon(
            onPressed: () => feed.toggleViewMode(),
            icon: Icon(
              feed.viewMode == FeedViewMode.latest
                  ? Icons.schedule
                  : Icons.view_list,
              size: 18,
            ),
            label: Text(
              feed.viewMode == FeedViewMode.latest ? 'Latest' : 'By source',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final sources = context.read<SourceProvider>().activeSources;
              feed.refresh(sources);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'about') {
                showAboutDialog(
                  context: context,
                  applicationName: 'Pluralis',
                  applicationVersion: '1.5.2',
                  children: [
                    const Text(
                      'E-ink friendly RSS reader with custom categories and lists.\nAdd feeds via URL or OPML import.',
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Pierre Gallaz · developed with Claude Code',
                      ),
                    ),
                  ],
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'about',
                child: Text('About'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryFilterBar(context, feed, sourceProvider),
          Expanded(
            child: _buildBody(context, feed, bookmarks, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar(
      BuildContext context, FeedProvider feed, SourceProvider sourceProvider) {
    final categories = sourceProvider.categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final selected = feed.selectedCategory ?? 'All';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _CategoryFilterChip(
            label: 'All',
            isSelected: selected == 'All',
            onTap: () => feed.selectCategory('All'),
          ),
          for (final cat in categories)
            _CategoryFilterChip(
              label: cat,
              isSelected: selected.toLowerCase() == cat.toLowerCase(),
              onTap: () => feed.selectCategory(cat),
            ),
        ],
      ),
    );
  }

  void _openArticle(BuildContext context, article, bool einkMode) {
    if (einkMode) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleReaderScreen(article: article),
        ),
      );
    } else {
      launchUrl(
        Uri.parse(article.link),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Widget _buildBody(BuildContext context, FeedProvider feed,
      BookmarkProvider bookmarks, SettingsProvider settings) {
    if (feed.isLoading && feed.allArticles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (feed.error != null && feed.allArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Failed to load feeds',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                final sources = context.read<SourceProvider>().activeSources;
                feed.refresh(sources);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (feed.articles.isEmpty) {
      final selectedCat = feed.selectedCategory;
      final emptyMessage = selectedCat != null
          ? 'No articles in "$selectedCat"\nAssign sources to this category in the Sources tab'
          : 'Pull down to refresh\nor enable sources in the Sources tab';

      return RefreshIndicator(
        onRefresh: () async {
          final sources = context.read<SourceProvider>().activeSources;
          await feed.refresh(sources);
        },
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Colors.grey[700]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (settings.einkMode) {
      return _buildPagedFeed(context, feed, bookmarks, settings);
    }

    return _buildScrollFeed(context, feed, bookmarks, settings);
  }

  /// Normal scrolling feed
  Widget _buildScrollFeed(BuildContext context, FeedProvider feed,
      BookmarkProvider bookmarks, SettingsProvider settings) {
    return RefreshIndicator(
      onRefresh: () async {
        final sources = context.read<SourceProvider>().activeSources;
        await feed.refresh(sources);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: feed.articles.length,
        itemBuilder: (context, index) {
          final article = feed.articles[index];
          return ArticleCard(
            article: article,
            isBookmarked: bookmarks.isBookmarked(article.id),
            onBookmarkToggle: () => bookmarks.toggle(article),
            onTap: () => _openArticle(context, article, settings.einkMode),
          );
        },
      ),
    );
  }

  /// E-ink paged feed — page-up / page-down navigation
  Widget _buildPagedFeed(BuildContext context, FeedProvider feed,
      BookmarkProvider bookmarks, SettingsProvider settings) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Rough estimate: each card ~120px, minus AppBar+NavBar+CategoryBar (~220px)
    final cardsPerPage = ((screenHeight - 220) / 120).floor().clamp(2, 10);
    final totalPages = (feed.articles.length / cardsPerPage).ceil();

    return _PagedFeedView(
      articles: feed.articles,
      bookmarks: bookmarks,
      cardsPerPage: cardsPerPage,
      totalPages: totalPages > 0 ? totalPages : 1,
      einkMode: settings.einkMode,
      onOpenArticle: (article) =>
          _openArticle(context, article, settings.einkMode),
      onRefresh: () async {
        final sources = context.read<SourceProvider>().activeSources;
        await feed.refresh(sources);
      },
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.black : Colors.black87,
              width: isSelected ? 1.5 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _PagedFeedView extends StatefulWidget {
  final List articles;
  final BookmarkProvider bookmarks;
  final int cardsPerPage;
  final int totalPages;
  final bool einkMode;
  final void Function(dynamic article) onOpenArticle;
  final Future<void> Function() onRefresh;

  const _PagedFeedView({
    required this.articles,
    required this.bookmarks,
    required this.cardsPerPage,
    required this.totalPages,
    required this.einkMode,
    required this.onOpenArticle,
    required this.onRefresh,
  });

  @override
  State<_PagedFeedView> createState() => _PagedFeedViewState();
}

class _PagedFeedViewState extends State<_PagedFeedView> {
  int _currentPage = 0;

  @override
  void didUpdateWidget(covariant _PagedFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= widget.totalPages) {
      _currentPage = (widget.totalPages - 1).clamp(0, widget.totalPages);
    }
  }

  void _nextPage() {
    if (_currentPage < widget.totalPages - 1) {
      setState(() => _currentPage++);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _currentPage * widget.cardsPerPage;
    final end = (start + widget.cardsPerPage).clamp(0, widget.articles.length);
    final pageArticles = widget.articles.sublist(start, end);

    return GestureDetector(
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          _nextPage(); // swipe up = next page
        } else if (velocity > 200) {
          _prevPage(); // swipe down = prev page
        }
      },
      child: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final article in pageArticles)
                  ArticleCard(
                    article: article,
                    isBookmarked: widget.bookmarks.isBookmarked(article.id),
                    onBookmarkToggle: () => widget.bookmarks.toggle(article),
                    onTap: () => widget.onOpenArticle(article),
                  ),
              ],
            ),
          ),
          // Page navigation bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _currentPage > 0 ? _prevPage : null,
                ),
                Text(
                  'Page ${_currentPage + 1} / ${widget.totalPages}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed:
                      _currentPage < widget.totalPages - 1 ? _nextPage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
