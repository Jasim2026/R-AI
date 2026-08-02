import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_session.dart';
import '../models/message.dart';

class SessionDatabaseService {
  static SessionDatabaseService? _instance;
  Database? _db;

  SessionDatabaseService._();

  static Future<SessionDatabaseService> getInstance() async {
    if (_instance == null) {
      _instance = SessionDatabaseService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'r_ai_sessions.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            model_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            message_count INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            content TEXT NOT NULL,
            role TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            is_streaming INTEGER DEFAULT 0,
            error TEXT,
            message_index INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_messages_session ON messages(session_id, message_index)',
        );
      },
    );
  }

  Future<List<ChatSession>> loadSessions() async {
    if (_db == null) return [];

    final rows = await _db!.query(
      'sessions',
      orderBy: 'updated_at DESC',
    );

    return rows.map((row) {
      return ChatSession(
        id: row['id'] as String,
        title: row['title'] as String,
        modelId: row['model_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        messages: [],
      );
    }).toList();
  }

  Future<List<Message>> loadMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (_db == null) return [];

    final rows = await _db!.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'message_index ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map((row) {
      return Message(
        id: row['id'] as String,
        content: row['content'] as String,
        role: MessageRole.values.firstWhere(
          (e) => e.name == row['role'],
          orElse: () => MessageRole.assistant,
        ),
        timestamp: DateTime.parse(row['timestamp'] as String),
        isStreaming: (row['is_streaming'] as int) == 1,
        error: row['error'] as String?,
      );
    }).toList();
  }

  Future<int> getMessageCount(String sessionId) async {
    if (_db == null) return 0;

    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE session_id = ?',
      [sessionId],
    );

    return result.first['count'] as int;
  }

  Future<void> saveSession(ChatSession session) async {
    if (_db == null) return;

    await _db!.insert(
      'sessions',
      {
        'id': session.id,
        'title': session.title,
        'model_id': session.modelId,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt.toIso8601String(),
        'message_count': session.messages.length,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Save all messages
    for (int i = 0; i < session.messages.length; i++) {
      final msg = session.messages[i];
      await _db!.insert(
        'messages',
        {
          'id': msg.id,
          'session_id': session.id,
          'content': msg.content,
          'role': msg.role.name,
          'timestamp': msg.timestamp.toIso8601String(),
          'is_streaming': msg.isStreaming ? 1 : 0,
          'error': msg.error,
          'message_index': i,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> updateSessionMeta(ChatSession session) async {
    if (_db == null) return;

    await _db!.update(
      'sessions',
      {
        'title': session.title,
        'updated_at': session.updatedAt.toIso8601String(),
        'message_count': session.messages.length,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    if (_db == null) return;

    await _db!.update(
      'sessions',
      {
        'title': newTitle,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    if (_db == null) return;

    await _db!.delete(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    await _db!.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
