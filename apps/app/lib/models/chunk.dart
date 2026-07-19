import 'dart:convert';

class Chunk {
  final String id;
  final String chapterId;
  final int chunkIndex;
  final String text;
  final List<double>? embedding; // nullable; only set after backend embedding
  final int? page;
  final DateTime createdAt;

  Chunk({
    required this.id,
    required this.chapterId,
    required this.chunkIndex,
    required this.text,
    this.embedding,
    this.page,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'chapterId': chapterId,
    'chunkIndex': chunkIndex,
    'text': text,
    'embeddingJson': embedding != null ? jsonEncode(embedding) : null,
    'page': page,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Chunk.fromMap(Map<String, dynamic> map) {
    List<double>? emb;
    if (map['embeddingJson'] != null) {
      final decoded = jsonDecode(map['embeddingJson'] as String) as List;
      emb = decoded.map((e) => (e as num).toDouble()).toList();
    }
    return Chunk(
      id: map['id'] as String,
      chapterId: map['chapterId'] as String,
      chunkIndex: map['chunkIndex'] as int,
      text: map['text'] as String,
      embedding: emb,
      page: map['page'] as int?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
