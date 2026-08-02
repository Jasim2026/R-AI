import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../services/litert_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import '../providers/rag_provider.dart';

enum InferenceBlockReason {
  none,
  noLlmModel,
  ragEnabledButNoEmbeddingModel,
  ragEnabledButNoDatabases,
}

class ChatProvider extends ChangeNotifier {
  final LiteRTService _litertService;
  final StorageService _storageService;
  final CacheService _cacheService;
  final RagProvider? _ragProvider;

  ChatSession? _currentSession;
  List<ChatSession> _sessions = [];
  bool _isGenerating = false;
  bool _isCancelled = false;
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;
  bool _sessionsLoaded = false;
  bool _modelsLoaded = false;

  ChatProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
    RagProvider? ragProvider,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService,
        _ragProvider = ragProvider;

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  bool get isGenerating => _isGenerating;
  bool get canStop => _isGenerating;
  RagProvider? get ragProvider => _ragProvider;

  InferenceBlockReason checkInferencePrerequisites() {
    final ragEnabled = _cacheService.ragEnabled;
    final llmLoaded = _litertService.currentModel != null;

    if (!llmLoaded) {
      return InferenceBlockReason.noLlmModel;
    }

    if (ragEnabled) {
      if (_ragProvider == null || !_ragProvider!.isLoaded) {
        return InferenceBlockReason.ragEnabledButNoEmbeddingModel;
      }
      if (!_ragProvider!.hasDbs) {
        return InferenceBlockReason.ragEnabledButNoDatabases;
      }
    }

    return InferenceBlockReason.none;
  }

  String getBlockReasonMessage(InferenceBlockReason reason) {
    switch (reason) {
      case InferenceBlockReason.none:
        return '';
      case InferenceBlockReason.noLlmModel:
        return 'No LLM model loaded. Import and load a model from the Models tab.';
      case InferenceBlockReason.ragEnabledButNoEmbeddingModel:
        return 'RAG is enabled but the embedding model is not loaded. '
            'Go to Settings > RAG Management to load an embedding model.';
      case InferenceBlockReason.ragEnabledButNoDatabases:
        return 'RAG is enabled but no document databases exist. '
            'Go to Settings > RAG Management to import documents.';
    }
  }

  Future<void> loadSessions() async {
    if (_sessionsLoaded) return;
    _sessions = await _storageService.loadAllChatSessions();
    _sessionsLoaded = true;
    notifyListeners();
  }

  Future<void> loadModelsIfNeeded(bool Function() isLoaded) async {
    if (_modelsLoaded) return;
    _modelsLoaded = true;
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

    final blockReason = checkInferencePrerequisites();
    if (blockReason != InferenceBlockReason.none) {
      final errorMessage = Message(
        content: getBlockReasonMessage(blockReason),
        role: MessageRole.assistant,
        error: blockReason.toString(),
      );
      if (_currentSession == null) {
        await createNewSession();
      }
      _currentSession!.addMessage(errorMessage);
      await _storageService.saveChatSession(_currentSession!);
      notifyListeners();
      return;
    }

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

  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds > 60) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _debouncedSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () {
      if (_currentSession != null) {
        _storageService.saveChatSession(_currentSession!);
      }
    });
  }

  Future<void> _generateResponse() async {
    _isGenerating = true;
    _isCancelled = false;
    _buffer.clear();
    notifyListeners();

    try {
      final lastUserMsg = _currentSession!.messages
          .where((m) => m.role == MessageRole.user)
          .lastOrNull;
      final userContent = lastUserMsg?.content ?? '';

      String promptToSend = userContent;
      bool usedRag = false;

      if (_cacheService.ragEnabled &&
          _ragProvider != null &&
          _ragProvider!.isLoaded &&
          _ragProvider!.hasDbs) {
        final topK = _cacheService.ragTopK;
        final results = await _ragProvider!.search(
          query: userContent,
          topK: topK,
        );

        if (results.isNotEmpty) {
          promptToSend = _ragProvider!.buildRagPrompt(
            userContent,
            results,
            _cacheService.systemPrompt,
          );
          usedRag = true;
        }
      }

      if (_cacheService.streamingEnabled) {
        final stream = _litertService.generateStream(
          prompt: promptToSend,
          systemInstruction: usedRag ? '' : _cacheService.systemPrompt,
          maxTokens: _cacheService.maxTokens,
          temperature: _cacheService.temperature,
          topP: _cacheService.topP,
          cachePrompt: _cacheService.cachePrompts,
        );

        await for (final token in stream) {
          if (_isCancelled) break;
          _buffer.write(token);

          if (_currentSession!.messages.isNotEmpty &&
              _currentSession!.messages.last.role ==
                  MessageRole.assistant &&
              _currentSession!.messages.last.isStreaming) {
            _currentSession!.messages.last = _currentSession!.messages.last
                .copyWith(content: _buffer.toString());
          } else {
            final assistantMessage = Message(
              content: _buffer.toString(),
              role: MessageRole.assistant,
              isStreaming: true,
            );
            _currentSession!.messages.add(assistantMessage);
          }
          _throttledNotify();
        }
      } else {
        final response = await _litertService.generate(
          prompt: promptToSend,
          systemInstruction: usedRag ? '' : _cacheService.systemPrompt,
          maxTokens: _cacheService.maxTokens,
          temperature: _cacheService.temperature,
          topP: _cacheService.topP,
          cachePrompt: _cacheService.cachePrompts,
        );
        _buffer.write(response);
      }

      if (!_isCancelled) {
        final finalResponse = _buffer.toString();
        if (_currentSession!.messages.isNotEmpty &&
            _currentSession!.messages.last.role == MessageRole.assistant) {
          _currentSession!.messages.last = _currentSession!.messages.last
              .copyWith(content: finalResponse, isStreaming: false);
        } else {
          final assistantMessage = Message(
            content: finalResponse,
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
              finalResponse,
            );
          }
        }
      }

      _debouncedSave();
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
      _buffer.clear();
      notifyListeners();
    }
  }

  Future<void> stopGeneration() async {
    _isCancelled = true;
    await _litertService.cancelGeneration();
    if (_currentSession != null && _buffer.isNotEmpty) {
      final assistantMessage = Message(
        content: _buffer.toString(),
        role: MessageRole.assistant,
      );
      if (_currentSession!.messages.isNotEmpty &&
          _currentSession!.messages.last.isStreaming) {
        _currentSession!.messages.last = assistantMessage;
      }
      await _storageService.saveChatSession(_currentSession!);
    }
    _isGenerating = false;
    _buffer.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
