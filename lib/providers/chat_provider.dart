import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../models/tool_definition.dart';
import '../services/litert_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import '../services/tool_service.dart';
import '../services/log_service.dart';
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
  final LogService _logService;

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

  // RAG search progress state
  bool _isRagSearching = false;
  double _ragProgress = 0.0;
  String _ragStatus = '';

  ChatProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
    RagProvider? ragProvider,
    ToolProvider? toolProvider,
    LogService? logService,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService,
        _ragProvider = ragProvider,
        _toolProvider = toolProvider,
        _logService = logService ?? LogService();

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  bool get isGenerating => _isGenerating;
  bool get canStop => _isGenerating;
  bool get usedRag => _usedRag;
  bool get isRagSearching => _isRagSearching;
  double get ragProgress => _ragProgress;
  String get ragStatus => _ragStatus;
  RagProvider? get ragProvider => _ragProvider;
  ToolProvider? get toolProvider => _toolProvider;

  InferenceBlockReason checkInferencePrerequisites() {
    final ragEnabled = _cacheService.ragEnabled;
    final llmLoaded = _litertService.currentModel != null;

    _logService.log('ChatProvider', 'Checking prerequisites: RAG enabled=$ragEnabled, LLM loaded=$llmLoaded');

    if (!llmLoaded) {
      _logService.log('ChatProvider', 'BLOCKED: No LLM model loaded');
      return InferenceBlockReason.noLlmModel;
    }

    _logService.log('ChatProvider', 'LLM model: ${_litertService.currentModel!.name} (${_litertService.currentModel!.id})');

    if (ragEnabled) {
      final ragLoaded = _ragProvider != null && _ragProvider!.isLoaded;
      final hasDbs = _ragProvider != null && _ragProvider!.hasDbs;
      _logService.log('ChatProvider', 'RAG checks: provider exists=${_ragProvider != null}, loaded=$ragLoaded, hasDBs=$hasDbs');

      if (!ragLoaded) {
        _logService.log('ChatProvider', 'BLOCKED: RAG enabled but embedding model not loaded');
        return InferenceBlockReason.ragEnabledButNoEmbeddingModel;
      }
      if (!hasDbs) {
        _logService.log('ChatProvider', 'BLOCKED: RAG enabled but no databases');
        return InferenceBlockReason.ragEnabledButNoDatabases;
      }
      _logService.log('ChatProvider', 'RAG ready: ${_ragProvider!.dbs.length} databases, dim=${_ragProvider!.embeddingDimension}');
    }

    _logService.log('ChatProvider', 'All prerequisites met');
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
    if (_sessionsLoaded) {
      _logService.log('ChatProvider', 'Sessions already loaded, skipping');
      return;
    }
    _logService.log('ChatProvider', 'Loading chat sessions...');
    try {
      _sessions = await _storageService.loadAllChatSessions();
      _sessionsLoaded = true;
      _logService.log('ChatProvider', 'Loaded ${_sessions.length} sessions');
      notifyListeners();
    } catch (e, stackTrace) {
      _logService.logError('ChatProvider', 'Failed to load sessions', e, stackTrace);
    }
  }

  Future<void> loadModelsIfNeeded(bool Function() isLoaded) async {
    if (_modelsLoaded) return;
    _modelsLoaded = true;
  }

  Future<void> createNewSession() async {
    _logService.log('ChatProvider', 'Creating new chat session');
    _currentSession = ChatSession(
      modelId: _litertService.currentModel?.id,
    );
    _sessions.insert(0, _currentSession!);
    await _storageService.saveChatSession(_currentSession!);
    _logService.log('ChatProvider', 'Session created: ${_currentSession!.id}');
    notifyListeners();
  }

  Future<void> selectSession(String sessionId) async {
    _logService.log('ChatProvider', 'Selecting session: $sessionId');
    _currentSession = _sessions.firstWhere((s) => s.id == sessionId);
    _logService.log('ChatProvider', 'Session selected: ${_currentSession!.messages.length} messages');
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    _logService.log('ChatProvider', 'Deleting session: $sessionId');
    _sessions.removeWhere((s) => s.id == sessionId);
    await _storageService.deleteChatSession(sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
      _logService.log('ChatProvider', 'Current session was deleted, switched to: ${_currentSession?.id ?? "none"}');
    }
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    _logService.log('ChatProvider', 'sendMessage called: "${content.length > 100 ? content.substring(0, 100) + "..." : content}"');

    if (content.trim().isEmpty || _isGenerating) {
      _logService.log('ChatProvider', 'sendMessage aborted: empty=${content.trim().isEmpty} generating=$_isGenerating');
      return;
    }

    final blockReason = checkInferencePrerequisites();
    if (blockReason != InferenceBlockReason.none) {
      _logService.log('ChatProvider', 'sendMessage blocked: ${blockReason.name}');
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
    _logService.log('ChatProvider', 'User message added to session. Total messages: ${_currentSession!.messages.length}');
    notifyListeners();

    // Check prompt cache
    if (_cacheService.cachePrompts && _litertService.currentModel != null) {
      final cached = _cacheService.getCachedResponse(
        _litertService.currentModel!.id,
        content,
      );
      if (cached != null) {
        _logService.log('ChatProvider', 'Cache HIT for this prompt, using cached response (${cached.length} chars)');
        final assistantMessage = Message(
          content: cached,
          role: MessageRole.assistant,
        );
        _currentSession!.addMessage(assistantMessage);
        await _storageService.saveChatSession(_currentSession!);
        notifyListeners();
        return;
      } else {
        _logService.log('ChatProvider', 'Cache MISS for this prompt');
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
        _logService.log('ChatProvider', 'Debounced save triggered');
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
      if (lower.contains(keyword)) {
        _logService.log('ChatProvider', 'Uncertainty detected: keyword "$keyword" found in response');
        return true;
      }
    }
    return false;
  }

  Future<String> _generateOnce(String prompt, String systemInstruction) async {
    _logService.log('ChatProvider', '_generateOnce: prompt=${prompt.length} chars, systemInstruction=${systemInstruction.length} chars');
    _logService.log('ChatProvider', 'Generation params: streaming=${_cacheService.streamingEnabled}, maxTokens=${_cacheService.maxTokens}, temp=${_cacheService.temperature}, topP=${_cacheService.topP}');

    if (_cacheService.streamingEnabled) {
      _logService.log('ChatProvider', 'Starting streaming generation...');
      final stream = _litertService.generateStream(
        prompt: prompt,
        systemInstruction: systemInstruction,
        maxTokens: _cacheService.maxTokens,
        temperature: _cacheService.temperature,
        topP: _cacheService.topP,
        cachePrompt: _cacheService.cachePrompts,
      );

      _buffer.clear();
      var tokenCount = 0;
      await for (final token in stream) {
        if (_isCancelled) {
          _logService.log('ChatProvider', 'Generation cancelled after $tokenCount tokens');
          break;
        }
        _buffer.write(token);
        tokenCount++;

        if (tokenCount % 50 == 0) {
          _logService.log('ChatProvider', 'Streaming: $tokenCount tokens received, ${_buffer.length} chars total');
        }

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
      _logService.log('ChatProvider', 'Streaming complete: $tokenCount tokens, ${_buffer.length} chars');
      return _buffer.toString();
    } else {
      _logService.log('ChatProvider', 'Starting non-streaming generation...');
      final response = await _litertService.generate(
        prompt: prompt,
        systemInstruction: systemInstruction,
        maxTokens: _cacheService.maxTokens,
        temperature: _cacheService.temperature,
        topP: _cacheService.topP,
        cachePrompt: _cacheService.cachePrompts,
      );
      _logService.log('ChatProvider', 'Non-streaming response: ${response.length} chars');
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

      _logService.log('ChatProvider', '=== Starting response generation ===');
      _logService.log('ChatProvider', 'User message: "${userContent.length > 100 ? userContent.substring(0, 100) + "..." : userContent}"');
      _logService.log('ChatProvider', 'RAG: enabled=$ragEnabled, mode=$ragMode');

      String promptToSend = userContent;
      String systemInstruction = _cacheService.systemPrompt;
      _logService.log('ChatProvider', 'System prompt: "${systemInstruction.length > 100 ? systemInstruction.substring(0, 100) + "..." : systemInstruction}"');

      // Pre-generation RAG
      if (ragMode == 'pre_generation' && ragEnabled) {
        _logService.log('ChatProvider', 'Pre-generation RAG: checking prerequisites...');
        if (_ragProvider != null && _ragProvider!.isLoaded && _ragProvider!.hasDbs) {
          final topK = _cacheService.ragTopK;
          _logService.log('ChatProvider', 'RAG search: topK=$topK');

          // Show RAG progress
          _isRagSearching = true;
          _ragProgress = 0.1;
          _ragStatus = 'Searching documents...';
          notifyListeners();

          // Small delay to show the progress bar
          await Future.delayed(const Duration(milliseconds: 100));

          _ragProgress = 0.3;
          _ragStatus = 'Embedding query...';
          notifyListeners();

          final results = await _ragProvider!.search(
            query: userContent,
            topK: topK,
          );

          _logService.log('ChatProvider', 'RAG search returned ${results.length} results');

          _ragProgress = 0.7;
          _ragStatus = 'Found ${results.length} relevant chunks';
          notifyListeners();

          await Future.delayed(const Duration(milliseconds: 200));

          if (results.isNotEmpty) {
            // Show context preview
            final firstChunkPreview = results.first.text.length > 50
                ? results.first.text.substring(0, 50) + '...'
                : results.first.text;
            _ragStatus = 'Using: "$firstChunkPreview"';
            _ragProgress = 0.9;
            notifyListeners();

            await Future.delayed(const Duration(milliseconds: 300));

            promptToSend = _ragProvider!.buildRagPrompt(
              userContent,
              results,
              _cacheService.systemPrompt,
            );
            systemInstruction = '';
            _usedRag = true;
            _logService.log('ChatProvider', 'RAG prompt built: ${promptToSend.length} chars');
          } else {
            _ragStatus = 'No matches found';
            _ragProgress = 1.0;
            notifyListeners();
            _logService.log('ChatProvider', 'No RAG results, using original query');
          }

          // Clear RAG progress
          _isRagSearching = false;
          _ragProgress = 0.0;
          _ragStatus = '';
          notifyListeners();
        } else {
          _logService.log('ChatProvider', 'RAG prerequisites not met, skipping');
        }
      }

      // Generate response
      _logService.log('ChatProvider', 'Calling _generateOnce...');
      final finalResponse = await _generateOnce(promptToSend, systemInstruction);
      _logService.log('ChatProvider', 'Generation complete: ${finalResponse.length} chars');

      if (!_isCancelled) {
        // Post-generation RAG
        if (ragMode == 'post_generation' && ragEnabled && !_usedRag) {
          _logService.log('ChatProvider', 'Post-generation RAG: checking for uncertainty...');
          if (_isUncertainResponse(finalResponse) &&
              _ragProvider != null &&
              _ragProvider!.isLoaded &&
              _ragProvider!.hasDbs) {
            _logService.log('ChatProvider', 'Response is uncertain, re-generating with RAG...');
            _usedRag = true;
            final topK = _cacheService.ragTopK;
            final results = await _ragProvider!.search(
              query: userContent,
              topK: topK,
            );

            _logService.log('ChatProvider', 'RAG search returned ${results.length} results for re-generation');

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
              _logService.log('ChatProvider', 'Re-generating with RAG prompt: ${ragPrompt.length} chars');
              final ragResponse = await _generateOnce(ragPrompt, '');
              _logService.log('ChatProvider', 'RAG re-generation complete: ${ragResponse.length} chars');

              if (!_isCancelled && _currentSession!.messages.isNotEmpty) {
                _currentSession!.messages.last = _currentSession!.messages.last
                    .copyWith(content: ragResponse, isStreaming: false);
              }
            }
          } else {
            _logService.log('ChatProvider', 'Response is certain, no RAG re-generation needed');
          }
        }

        // Finalize message
        if (_currentSession!.messages.isNotEmpty &&
            _currentSession!.messages.last.role == MessageRole.assistant) {
          final content = _currentSession!.messages.last.content;
          _currentSession!.messages.last = _currentSession!.messages.last
              .copyWith(content: content, isStreaming: false);
        }

        // Tool calling
        if (_toolProvider != null && _toolProvider!.toolCallingEnabled) {
          final responseText = _currentSession!.messages.isNotEmpty
              ? _currentSession!.messages.last.content
              : '';

          _logService.log('ChatProvider', 'Checking for tool calls in response...');
          final toolCall = _toolProvider!.detectToolCall(responseText);
          if (toolCall != null) {
            _logService.log('ChatProvider', 'Tool call detected: ${toolCall.tool.name} (${toolCall.tool.detectionType.name})');
            _logService.log('ChatProvider', 'Detected text: "${toolCall.detectedText}"');

            final toolResult = await _toolProvider!.executeTool(toolCall);
            _logService.log('ChatProvider', 'Tool execution: success=${toolResult.success}, error=${toolResult.error ?? "none"}');

            // Add tool call info as a system-like message
            final toolMsg = Message(
              content: '🔧 **Tool Called:** ${toolCall.tool.name}\n'
                  'Detection: ${toolCall.tool.detectionType.name} — "${toolCall.detectedText}"\n'
                  '${toolResult.success ? "✅ Success" : "❌ Failed: ${toolResult.error}"}',
              role: MessageRole.assistant,
            );
            _currentSession!.addMessage(toolMsg);
          } else {
            _logService.log('ChatProvider', 'No tool calls detected');
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
              _logService.log('ChatProvider', 'Caching response for model ${_litertService.currentModel!.id}');
              await _cacheService.savePromptCache(
                _litertService.currentModel!.id,
                lastUserMsg.content,
                lastAssistant.content,
              );
            }
          }
        }
      }

      _logService.log('ChatProvider', '=== Response generation complete ===');
      _debouncedSave();
    } catch (e, stackTrace) {
      _logService.logError('ChatProvider', 'Error during response generation', e, stackTrace);
      final errorMessage = Message(
        content: 'Error: $e',
        role: MessageRole.assistant,
        error: e.toString(),
      );
      _currentSession!.addMessage(errorMessage);
      await _storageService.saveChatSession(_currentSession!);
    } finally {
      _isGenerating = false;
      _isRagSearching = false;
      _ragProgress = 0.0;
      _ragStatus = '';
      _buffer.clear();
      notifyListeners();
    }
  }

  Future<void> stopGeneration() async {
    _logService.log('ChatProvider', 'Stopping generation...');
    _isCancelled = true;
    await _litertService.cancelGeneration();
    if (_currentSession != null && _buffer.isNotEmpty) {
      _logService.log('ChatProvider', 'Saving partial response: ${_buffer.length} chars');
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
    _isRagSearching = false;
    _ragProgress = 0.0;
    _ragStatus = '';
    _buffer.clear();
    _logService.log('ChatProvider', 'Generation stopped');
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
