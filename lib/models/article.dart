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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'link': link,
        'publishedAt': publishedAt?.millisecondsSinceEpoch,
        'sourceName': sourceName,
        'sourceId': sourceId,
        'category': category,
        'lang': lang,
        'fullContent': fullContent,
      };

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
        link: json['link'] as String,
        publishedAt: json['publishedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['publishedAt'] as int)
            : null,
        sourceName: json['sourceName'] as String,
        sourceId: json['sourceId'] as String,
        category: (json['category'] as String?) ?? '',
        lang: (json['lang'] as String?) ?? 'EN',
        fullContent: json['fullContent'] as String?,
      );
}
