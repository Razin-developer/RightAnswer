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
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
