import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

class RagContext {
  final String text;
  final double score;
  final String dbName;
  final int chunkId;

  RagContext({
    required this.text,
    required this.score,
    required this.dbName,
    required this.chunkId,
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'score': score,
    'dbName': dbName,
    'chunkId': chunkId,
  };

  factory RagContext.fromMap(Map<String, dynamic> m) => RagContext(
    text: m['text'] ?? '',
    score: (m['score'] ?? 0).toDouble(),
    dbName: m['dbName'] ?? '',
    chunkId: m['chunkId'] ?? 0,
  );
}

class Message {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final bool isStreaming;
  final String? error;
  final List<RagContext>? ragContexts;

  Message({
    String? id,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.isStreaming = false,
    this.error,
    this.ragContexts,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? content,
    bool? isStreaming,
    String? error,
    List<RagContext>? ragContexts,
  }) {
    return Message(
      id: id,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
      ragContexts: ragContexts ?? this.ragContexts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'role': role.name,
      'timestamp': timestamp.toIso8601String(),
      if (ragContexts != null && ragContexts!.isNotEmpty)
        'ragContexts': ragContexts!.map((r) => r.toMap()).toList(),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    List<RagContext>? contexts;
    if (map['ragContexts'] != null) {
      contexts = (map['ragContexts'] as List)
          .map((r) => RagContext.fromMap(r as Map<String, dynamic>))
          .toList();
    }
    return Message(
      id: map['id'],
      content: map['content'],
      role: MessageRole.values.firstWhere((e) => e.name == map['role']),
      timestamp: DateTime.parse(map['timestamp']),
      ragContexts: contexts,
    );
  }
}