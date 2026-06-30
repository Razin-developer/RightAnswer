class ChatMessage {
  final String id;
  final String chatId;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imagePath;
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
    required this.responseLength,
    required this.reasoningLevel,
    required this.tokenCount,
    required this.cost,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  Map<String, dynamic> toMap() => {
    'id': id,
    'chatId': chatId,
    'role': role,
    'content': content,
    'imagePath': imagePath,
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
    responseLength: (m['responseLength'] as String?) ?? 'normal',
    reasoningLevel: (m['reasoningLevel'] as String?) ?? 'mid',
    tokenCount: (m['tokenCount'] as int?) ?? 0,
    cost: ((m['cost'] as num?)?.toDouble()) ?? 0.0,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
