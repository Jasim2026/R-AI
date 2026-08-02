import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../services/litert_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

class ChatProvider extends ChangeNotifier {
  final LiteRTService _litertService;
  final StorageService _storageService;
  final CacheService _cacheService;

  ChatSession? _currentSession;
  List<ChatSession> _sessions = [];
  bool _isGenerating = false;
  bool _isCancelled = false;
  String _currentResponse = '';

  ChatProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService;

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  bool get isGenerating => _isGenerating;
  bool get canStop => _isGenerating;

  Future<void> loadSessions() async {
    _sessions = await _storageService.loadAllChatSessions();
    notifyListeners();
  }

  Future<void> createNewSession() async {
    _currentSession = ChatSession(
      modelId: _litertService.currentModel?.id,
    );
    _sessions.insert(0, _currentSession!);
    await _storageService.saveChatSession(_currentSession!);
    notifyListeners();
  }

  Future<void> selectSession(String sessionId) async {
    _currentSession = _sessions.firstWhere((s) => s.id == sessionId);
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
    await _storageService.deleteChatSession(sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty || _isGenerating) return;

    if (_currentSession == null) {
      await createNewSession();
    }

    final userMessage = Message(
      content: content.trim(),
      role: MessageRole.user,
    );

    _currentSession!.addMessage(userMessage);
    await _storageService.saveChatSession(_currentSession!);
    notifyListeners();

    if (_cacheService.cachePrompts && _litertService.currentModel != null) {
      final cached = _cacheService.getCachedResponse(
        _litertService.currentModel!.id,
        content,
      );
      if (cached != null) {
        final assistantMessage = Message(
          content: cached,
          role: MessageRole.assistant,
        );
        _currentSession!.addMessage(assistantMessage);
        await _storageService.saveChatSession(_currentSession!);
        notifyListeners();
        return;
      }
    }

    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    _isGenerating = true;
    _isCancelled = false;
    _currentResponse = '';
    notifyListeners();

    try {
      // Get just the last user message content — the native Conversation
      // handles chat history internally
      final lastUserMsg = _currentSession!.messages
          .where((m) => m.role == MessageRole.user)
          .lastOrNull;
      final userContent = lastUserMsg?.content ?? '';

      if (_cacheService.streamingEnabled) {
        final stream = _litertService.generateStream(
          prompt: userContent,
          systemInstruction: _cacheService.systemPrompt,
          maxTokens: _cacheService.maxTokens,
          temperature: _cacheService.temperature,
          topP: _cacheService.topP,
          cachePrompt: _cacheService.cachePrompts,
        );

        await for (final token in stream) {
          if (_isCancelled) break;
          _currentResponse += token;

          if (_currentSession!.messages.isNotEmpty &&
              _currentSession!.messages.last.role ==
                  MessageRole.assistant &&
              _currentSession!.messages.last.isStreaming) {
            _currentSession!.messages.last = _currentSession!.messages.last
                .copyWith(content: _currentResponse);
          } else {
            final assistantMessage = Message(
              content: _currentResponse,
              role: MessageRole.assistant,
              isStreaming: true,
            );
            _currentSession!.messages.add(assistantMessage);
          }
          notifyListeners();
        }
      } else {
        _currentResponse = await _litertService.generate(
          prompt: userContent,
          systemInstruction: _cacheService.systemPrompt,
          maxTokens: _cacheService.maxTokens,
          temperature: _cacheService.temperature,
          topP: _cacheService.topP,
          cachePrompt: _cacheService.cachePrompts,
        );
      }

      if (!_isCancelled) {
        if (_currentSession!.messages.isNotEmpty &&
            _currentSession!.messages.last.role == MessageRole.assistant) {
          _currentSession!.messages.last = _currentSession!.messages.last
              .copyWith(content: _currentResponse, isStreaming: false);
        } else {
          final assistantMessage = Message(
            content: _currentResponse,
            role: MessageRole.assistant,
          );
          _currentSession!.addMessage(assistantMessage);
        }

        if (_cacheService.cachePrompts &&
            _litertService.currentModel != null) {
          final lastUserMsg = _currentSession!.messages
              .where((m) => m.role == MessageRole.user)
              .lastOrNull;
          if (lastUserMsg != null) {
            await _cacheService.savePromptCache(
              _litertService.currentModel!.id,
              lastUserMsg.content,
              _currentResponse,
            );
          }
        }
      }

      await _storageService.saveChatSession(_currentSession!);
    } catch (e) {
      final errorMessage = Message(
        content: 'Error: $e',
        role: MessageRole.assistant,
        error: e.toString(),
      );
      _currentSession!.addMessage(errorMessage);
      await _storageService.saveChatSession(_currentSession!);
    } finally {
      _isGenerating = false;
      _currentResponse = '';
      notifyListeners();
    }
  }

  String _buildPrompt() {
    final buffer = StringBuffer();
    buffer.writeln(_cacheService.systemPrompt);
    buffer.writeln();

    for (final message in _currentSession!.messages) {
      if (message.error != null) continue;
      switch (message.role) {
        case MessageRole.user:
          buffer.writeln('User: ${message.content}');
          break;
        case MessageRole.assistant:
          buffer.writeln('Assistant: ${message.content}');
          break;
        case MessageRole.system:
          buffer.writeln('System: ${message.content}');
          break;
      }
    }

    buffer.write('Assistant: ');
    return buffer.toString();
  }

  Future<void> stopGeneration() async {
    _isCancelled = true;
    await _litertService.cancelGeneration();
    if (_currentSession != null && _currentResponse.isNotEmpty) {
      final assistantMessage = Message(
        content: _currentResponse,
        role: MessageRole.assistant,
      );
      if (_currentSession!.messages.isNotEmpty &&
          _currentSession!.messages.last.isStreaming) {
        _currentSession!.messages.last = assistantMessage;
      }
      await _storageService.saveChatSession(_currentSession!);
    }
    _isGenerating = false;
    _currentResponse = '';
    notifyListeners();
  }
}