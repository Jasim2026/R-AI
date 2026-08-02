import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../services/session_database_service.dart';

class SessionProvider extends ChangeNotifier {
  final SessionDatabaseService _dbService;

  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  bool _isLoadingSessions = false;
  bool _isLoadingMessages = false;
  int _messageOffset = 0;
  static const int _messagePageSize = 50;
  bool _hasMoreMessages = true;

  SessionProvider({required SessionDatabaseService dbService})
      : _dbService = dbService;

  List<ChatSession> get sessions => _sessions;
  ChatSession? get currentSession => _currentSession;
  bool get isLoadingSessions => _isLoadingSessions;
  bool get isLoadingMessages => _isLoadingMessages;
  bool get hasMoreMessages => _hasMoreMessages;

  Future<void> loadSessions() async {
    _isLoadingSessions = true;
    notifyListeners();

    _sessions = await _dbService.loadSessions();
    _isLoadingSessions = false;
    notifyListeners();
  }

  Future<void> openSession(String sessionId) async {
    _messageOffset = 0;
    _hasMoreMessages = true;

    final existing = _sessions.where((s) => s.id == sessionId);
    if (existing.isNotEmpty) {
      _currentSession = existing.first;
      _currentSession!.messages.clear();
    } else {
      return;
    }

    notifyListeners();
    await loadMoreMessages();
  }

  Future<void> loadMoreMessages() async {
    if (_currentSession == null || !_hasMoreMessages || _isLoadingMessages) return;

    _isLoadingMessages = true;
    notifyListeners();

    final messages = await _dbService.loadMessages(
      _currentSession!.id,
      limit: _messagePageSize,
      offset: _messageOffset,
    );

    if (messages.length < _messagePageSize) {
      _hasMoreMessages = false;
    }

    _currentSession!.messages.insertAll(0, messages.reversed);
    _messageOffset += messages.length;

    _isLoadingMessages = false;
    notifyListeners();
  }

  Future<void> createSession({String? modelId, String? title}) async {
    final session = ChatSession(
      modelId: modelId,
      title: title ?? 'New Chat',
    );

    await _dbService.saveSession(session);
    _sessions.insert(0, session);
    _currentSession = session;
    _messageOffset = 0;
    _hasMoreMessages = false;

    notifyListeners();
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    await _dbService.renameSession(sessionId, newTitle);
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _sessions[idx].title = newTitle;
    }
    if (_currentSession?.id == sessionId) {
      _currentSession!.title = newTitle;
    }
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await _dbService.deleteSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
    }
    notifyListeners();
  }

  void addMessageToCurrent(Message message) {
    if (_currentSession == null) return;
    _currentSession!.addMessage(message);
    notifyListeners();
  }

  void updateLastMessage(Message message) {
    if (_currentSession == null || _currentSession!.messages.isEmpty) return;
    _currentSession!.messages.last = message;
    notifyListeners();
  }

  Future<void> saveSession(ChatSession session) async {
    await _dbService.saveSession(session);
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _sessions[idx] = session;
    }
    notifyListeners();
  }

  Future<void> loadFullSession(String sessionId) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;

    _currentSession = _sessions[idx];
    _currentSession!.messages.clear();

    final messages = await _dbService.loadMessages(sessionId, limit: 10000);
    _currentSession!.messages.addAll(messages);
    _hasMoreMessages = false;

    notifyListeners();
  }
}
