import 'dart:convert';

class ChatMessage {
  final String id;
  final String chatId;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imagePath;
  final String? responseLanguage;
  final String responseLength; // 'small' | 'normal' | 'large'
  final String reasoningLevel; // 'low' | 'mid' | 'high'
  final int tokenCount;
  final double cost;
  final List<String> sourceChunks;
  // Rich-answer envelope extras (from `richAnswer: true` chat responses).
  // `blocks` is the raw, defensively-typed list of block objects the backend
  // returned (may be null/empty — the baseline markdown path always works
  // regardless). `sources` are structured {text, pageNumber, subjectName,
  // chapterName} entries, richer than the plain-text `sourceChunks` above.
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>> sources;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.imagePath,
    this.responseLanguage,
    required this.responseLength,
    required this.reasoningLevel,
    required this.tokenCount,
    required this.cost,
    this.sourceChunks = const [],
    this.blocks,
    this.sources = const [],
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? role,
    String? content,
    String? imagePath,
    String? responseLanguage,
    String? responseLength,
    String? reasoningLevel,
    int? tokenCount,
    double? cost,
    List<String>? sourceChunks,
    List<Map<String, dynamic>>? blocks,
    List<Map<String, dynamic>>? sources,
    DateTime? createdAt,
  }) => ChatMessage(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    role: role ?? this.role,
    content: content ?? this.content,
    imagePath: imagePath ?? this.imagePath,
    responseLanguage: responseLanguage ?? this.responseLanguage,
    responseLength: responseLength ?? this.responseLength,
    reasoningLevel: reasoningLevel ?? this.reasoningLevel,
    tokenCount: tokenCount ?? this.tokenCount,
    cost: cost ?? this.cost,
    sourceChunks: sourceChunks ?? this.sourceChunks,
    blocks: blocks ?? this.blocks,
    sources: sources ?? this.sources,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'chatId': chatId,
    'role': role,
    'content': content,
    'imagePath': imagePath,
    'responseLanguage': responseLanguage,
    'responseLength': responseLength,
    'reasoningLevel': reasoningLevel,
    'tokenCount': tokenCount,
    'cost': cost,
    'sourceChunks': sourceChunks.isEmpty ? null : jsonEncode(sourceChunks),
    'blocks': (blocks == null || blocks!.isEmpty) ? null : jsonEncode(blocks),
    'sources': sources.isEmpty ? null : jsonEncode(sources),
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    chatId: m['chatId'] as String,
    role: m['role'] as String,
    content: m['content'] as String,
    imagePath: m['imagePath'] as String?,
    responseLanguage: m['responseLanguage'] as String?,
    responseLength: (m['responseLength'] as String?) ?? 'normal',
    reasoningLevel: (m['reasoningLevel'] as String?) ?? 'mid',
    tokenCount: (m['tokenCount'] as int?) ?? 0,
    cost: ((m['cost'] as num?)?.toDouble()) ?? 0.0,
    sourceChunks: m['sourceChunks'] != null
        ? List<String>.from(jsonDecode(m['sourceChunks'] as String) as List)
        : [],
    blocks: _decodeMaps(m['blocks']),
    sources: _decodeMaps(m['sources']) ?? const [],
    createdAt: DateTime.parse(m['createdAt'] as String),
  );

  static List<Map<String, dynamic>>? _decodeMaps(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.whereType<Map>().map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    } catch (_) {
      return null;
    }
  }
}
