import 'package:uuid/uuid.dart';
import 'message.dart';

class ChatSession {
  final String id;
  String title;
  final List<Message> messages;
  final DateTime createdAt;
  DateTime updatedAt;
  final String? modelId;

  ChatSession({
    String? id,
    this.title = 'New Chat',
    List<Message>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.modelId,
  })  : id = id ?? const Uuid().v4(),
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get messageCount => messages.length;

  Message? get lastMessage =>
      messages.isNotEmpty ? messages.last : null;

  void addMessage(Message message) {
    messages.add(message);
    updatedAt = DateTime.now();
    if (messages.length == 1 && message.role == MessageRole.user) {
      title = message.content.length > 40
          ? '${message.content.substring(0, 40)}...'
          : message.content;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'modelId': modelId,
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'],
      title: map['title'],
      messages: (map['messages'] as List)
          .map((m) => Message.fromMap(m))
          .toList(),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      modelId: map['modelId'],
    );
  }
}