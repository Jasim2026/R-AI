import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

class Message {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final bool isStreaming;
  final String? error;

  Message({
    String? id,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.isStreaming = false,
    this.error,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? content,
    bool? isStreaming,
    String? error,
  }) {
    return Message(
      id: id,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'role': role.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      content: map['content'],
      role: MessageRole.values.firstWhere((e) => e.name == map['role']),
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}