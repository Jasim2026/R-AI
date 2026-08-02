import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../models/tool_definition.dart';
import '../services/litert_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import '../services/tool_service.dart';
import '../providers/rag_provider.dart';
import '../providers/tool_provider.dart';

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
  final ToolProvider? _toolProvider;

  ChatSession? _currentSession;
  List<ChatSession> _sessions = [];
  bool _isGenerating = false;
  bool _isCancelled = false;
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;
  bool _sessionsLoaded = false;
  bool _modelsLoaded = false;
  bool _usedRag = false;

  ChatProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
    RagProvider? ragProvider,
    ToolProvider? toolProvider,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService,
        _ragProvider = ragProvider,
        _toolProvider = toolProvider;

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  bool get isGenerating => _isGenerating;
  bool get canStop => _isGenerating;
  bool get usedRag => _usedRag;
  RagProvider? get ragProvider => _ragProvider;
  ToolProvider? get toolProvider => _toolProvider;

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

  bool _isUncertainResponse(String response) {
    final keywords = _cacheService.uncertaintyKeywords
        .split(',')
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty)
        .toList();

    final lower = response.toLowerCase();
    for (final keyword in keywords) {
      if (lower.contains(keyword)) return true;
    }
    return false;
  }

  Future<String> _generateOnce(String prompt, String systemInstruction) async {
    if (_cacheService.streamingEnabled) {
      final stream = _litertService.generateStream(
        prompt: prompt,
        systemInstruction: systemInstruction,
        maxTokens: _cacheService.maxTokens,
        temperature: _cacheService.temperature,
        topP: _cacheService.topP,
        cachePrompt: _cacheService.cachePrompts,
      );

      _buffer.clear();
      await for (final token in stream) {
        if (_isCancelled) break;
        _buffer.write(token);

        if (_currentSession!.messages.isNotEmpty &&
            _currentSession!.messages.last.role == MessageRole.assistant &&
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
      return _buffer.toString();
    } else {
      final response = await _litertService.generate(
        prompt: prompt,
        systemInstruction: systemInstruction,
        maxTokens: _cacheService.maxTokens,
        temperature: _cacheService.temperature,
        topP: _cacheService.topP,
        cachePrompt: _cacheService.cachePrompts,
      );
      return response;
    }
  }

  Future<void> _generateResponse() async {
    _isGenerating = true;
    _isCancelled = false;
    _buffer.clear();
    _usedRag = false;
    notifyListeners();

    try {
      final lastUserMsg = _currentSession!.messages
          .where((m) => m.role == MessageRole.user)
          .lastOrNull;
      final userContent = lastUserMsg?.content ?? '';
      final ragMode = _cacheService.ragMode;
      final ragEnabled = _cacheService.ragEnabled;

      String promptToSend = userContent;
      String systemInstruction = _cacheService.systemPrompt;

      if (ragMode == 'pre_generation' && ragEnabled) {
        // Pre-generation RAG: embed query BEFORE generation
        if (_ragProvider != null && _ragProvider!.isLoaded && _ragProvider!.hasDbs) {
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
            systemInstruction = '';
            _usedRag = true;
          }
        }
      }

      // Generate response
      final finalResponse = await _generateOnce(promptToSend, systemInstruction);

      if (!_isCancelled) {
        // Post-generation RAG: check uncertainty AFTER generation
        if (ragMode == 'post_generation' && ragEnabled && !_usedRag) {
          if (_isUncertainResponse(finalResponse) &&
              _ragProvider != null &&
              _ragProvider!.isLoaded &&
              _ragProvider!.hasDbs) {
            // Model is uncertain — re-generate with RAG context
            _usedRag = true;
            final topK = _cacheService.ragTopK;
            final results = await _ragProvider!.search(
              query: userContent,
              topK: topK,
            );

            if (results.isNotEmpty) {
              final ragPrompt = _ragProvider!.buildRagPrompt(
                userContent,
                results,
                _cacheService.systemPrompt,
              );

              // Replace streaming message with fresh generation
              if (_currentSession!.messages.isNotEmpty &&
                  _currentSession!.messages.last.role == MessageRole.assistant) {
                _currentSession!.messages.last =
                    _currentSession!.messages.last.copyWith(
                  content: '',
                  isStreaming: true,
                );
              }

              _buffer.clear();
              final ragResponse = await _generateOnce(ragPrompt, '');

              if (!_isCancelled && _currentSession!.messages.isNotEmpty) {
                _currentSession!.messages.last = _currentSession!.messages.last
                    .copyWith(content: ragResponse, isStreaming: false);
              }
            }
          }
        }

        // Finalize message
        if (_currentSession!.messages.isNotEmpty &&
            _currentSession!.messages.last.role == MessageRole.assistant) {
          final content = _currentSession!.messages.last.content;
          _currentSession!.messages.last = _currentSession!.messages.last
              .copyWith(content: content, isStreaming: false);
        }

        // Tool calling: detect tool calls in response
        if (_toolProvider != null && _toolProvider!.toolCallingEnabled) {
          final responseText = _currentSession!.messages.isNotEmpty
              ? _currentSession!.messages.last.content
              : '';

          final toolCall = _toolProvider!.detectToolCall(responseText);
          if (toolCall != null) {
            final toolResult = await _toolProvider!.executeTool(toolCall);

            // Add tool call info as a system-like message
            final toolMsg = Message(
              content: '🔧 **Tool Called:** ${toolCall.tool.name}\n'
                  'Detection: ${toolCall.tool.detectionType.name} — "${toolCall.detectedText}"\n'
                  '${toolResult.success ? "✅ Success" : "❌ Failed: ${toolResult.error}"}',
              role: MessageRole.assistant,
            );
            _currentSession!.addMessage(toolMsg);
          }
        }

        // Cache the response
        if (_cacheService.cachePrompts && _litertService.currentModel != null) {
          final lastUserMsg = _currentSession!.messages
              .where((m) => m.role == MessageRole.user)
              .lastOrNull;
          if (lastUserMsg != null && _currentSession!.messages.isNotEmpty) {
            final lastAssistant = _currentSession!.messages
                .where((m) => m.role == MessageRole.assistant && !m.isStreaming)
                .lastOrNull;
            if (lastAssistant != null) {
              await _cacheService.savePromptCache(
                _litertService.currentModel!.id,
                lastUserMsg.content,
                lastAssistant.content,
              );
            }
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
