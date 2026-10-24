import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/article.dart';
import '../providers/settings_provider.dart';
import 'category_badge.dart';

class ArticleCard extends StatelessWidget {
  final Article article;
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final VoidCallback onTap;

  const ArticleCard({
    super.key,
    required this.article,
    required this.isBookmarked,
    required this.onBookmarkToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fs = settings.fontSize;
    final isEink = settings.einkMode;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: isEink ? 0 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isEink
            ? const BorderSide(color: Colors.black26, width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: fs,
                  height: 1.3,
                  color: isEink ? Colors.black : null,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (article.category.isNotEmpty &&
                      article.category != 'custom') ...[
                    CategoryBadge(category: article.category),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      article.sourceName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fs - 3,
                        color: isEink
                            ? Colors.black87
                            : (kCategoryColors[article.category.toLowerCase()] ??
                                const Color(0xFF1A3A5C)),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (article.publishedAt != null) ...[
                    Text(
                      ' · ${DateFormat.MMMd().add_Hm().format(article.publishedAt!)}',
                      style: TextStyle(
                        fontSize: fs - 3,
                        color: isEink ? Colors.black54 : Colors.grey[600],
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: onBookmarkToggle,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        isBookmarked ? Icons.star : Icons.star_border,
                        color: isBookmarked
                            ? const Color(0xFFE8A020)
                            : (isEink ? Colors.black54 : Colors.grey),
                        size: fs + 4,
                      ),
                    ),
                  ),
                ],
              ),
              if (article.description != null &&
                  article.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  article.description!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fs - 2,
                    color: isEink ? Colors.black87 : Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
