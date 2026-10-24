class Article {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final String link;
  final DateTime? publishedAt;
  final String sourceName;
  final String sourceId;
  String category;
  final String lang;
  final String? fullContent; // content:encoded from RSS, if available

  Article({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    required this.link,
    this.publishedAt,
    required this.sourceName,
    required this.sourceId,
    this.category = '',
    required this.lang,
    this.fullContent,
  });
}
