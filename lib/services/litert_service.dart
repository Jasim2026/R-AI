import 'dart:async';
import 'package:flutter/services.dart';
import '../models/llm_model.dart';
import '../services/log_service.dart';

class ModelMetadata {
  final List<BackendType> supportedBackends;
  final String? detectedParams;

  ModelMetadata({
    required this.supportedBackends,
    this.detectedParams,
  });
}

class LiteRTService {
  static const MethodChannel _channel = MethodChannel('com.rai/litert');
  static const EventChannel _eventChannel = EventChannel('com.rai/litert_stream');
  static final LogService _logService = LogService();

  bool _isInitialized = false;
  bool _isModelLoaded = false;
  LLMModel? _currentModel;
  StreamSubscription? _streamSubscription;

  bool get isInitialized => _isInitialized;
  bool get isModelLoaded => _isModelLoaded;
  LLMModel? get currentModel => _currentModel;

  Future<void> initialize() async {
    _logService.log('LiteRTService', 'Initializing LiteRT engine...');
    try {
      await _channel.invokeMethod('initialize');
      _isInitialized = true;
      _logService.log('LiteRTService', 'LiteRT engine initialized successfully');
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Failed to initialize LiteRT', e, null);
      throw Exception('Failed to initialize LiteRT: ${e.message}');
    }
  }

  Future<ModelMetadata> readModelMetadata(String modelPath) async {
    _logService.log('LiteRTService', 'Reading model metadata: $modelPath');
    if (!_isInitialized) {
      _logService.log('LiteRTService', 'Not initialized, initializing first...');
      await initialize();
    }

    try {
      final result = await _channel.invokeMethod('readModelMetadata', {
        'modelPath': modelPath,
      });

      _logService.log('LiteRTService', 'Raw metadata result: $result');

      final backends = (result['supportedBackends'] as List)
          .map((b) => BackendType.values.firstWhere(
                (e) => e.name == b,
                orElse: () => BackendType.cpu,
              ))
          .toList();

      final metadata = ModelMetadata(
        supportedBackends: backends,
        detectedParams: result['detectedParams'] as String?,
      );

      _logService.log('LiteRTService', 'Supported backends: ${backends.map((b) => b.name).join(", ")}');
      _logService.log('LiteRTService', 'Detected params: ${metadata.detectedParams ?? "none"}');

      return metadata;
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Failed to read model metadata', e, null);
      throw Exception('Failed to read model metadata: ${e.message}');
    }
  }

  Future<void> loadModel(LLMModel model) async {
    _logService.log('LiteRTService', '=== Loading LLM model ===');
    _logService.log('LiteRTService', 'Model: ${model.name} (${model.id})');
    _logService.log('LiteRTService', 'Path: ${model.path}');
    _logService.log('LiteRTService', 'Backend: ${model.backendName}');
    _logService.log('LiteRTService', 'Cache dir: ${model.cacheDir ?? "none"}');

    if (!_isInitialized) {
      _logService.log('LiteRTService', 'Not initialized, initializing first...');
      await initialize();
    }

    try {
      _logService.log('LiteRTService', 'Calling native loadModel...');
      await _channel.invokeMethod('loadModel', {
        'modelPath': model.path,
        'backend': model.backendName,
        'cacheDir': model.cacheDir,
      });
      _currentModel = model;
      _isModelLoaded = true;
      _logService.log('LiteRTService', '=== Model loaded successfully ===');
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Failed to load model', e, null);
      throw Exception('Failed to load model: ${e.message}');
    }
  }

  Future<void> unloadModel() async {
    if (!_isModelLoaded) {
      _logService.log('LiteRTService', 'No model loaded, skipping unload');
      return;
    }

    _logService.log('LiteRTService', 'Unloading model: ${_currentModel?.name ?? "unknown"}');
    _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _channel.invokeMethod('unloadModel');
      _logService.log('LiteRTService', 'Model unloaded successfully');
      _currentModel = null;
      _isModelLoaded = false;
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Failed to unload model', e, null);
      throw Exception('Failed to unload model: ${e.message}');
    }
  }

  Stream<String> generateStream({
    required String prompt,
    String? systemInstruction,
    int maxTokens = 4096,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 10,
    bool cachePrompt = false,
  }) async* {
    _logService.log('LiteRTService', '=== Starting streaming generation ===');
    _logService.log('LiteRTService', 'Prompt: "${prompt.length > 100 ? prompt.substring(0, 100) + "..." : prompt}" (${prompt.length} chars)');
    _logService.log('LiteRTService', 'System instruction: "${(systemInstruction ?? "").length > 100 ? (systemInstruction ?? "").substring(0, 100) + "..." : systemInstruction ?? ""}" (${(systemInstruction ?? "").length} chars)');
    _logService.log('LiteRTService', 'Params: maxTokens=$maxTokens, temp=$temperature, topP=$topP, topK=$topK, cachePrompt=$cachePrompt');

    if (!_isModelLoaded) {
      _logService.log('LiteRTService', 'ERROR: No model loaded');
      throw Exception('No model loaded. Load a model first.');
    }

    try {
      _logService.log('LiteRTService', 'Setting up broadcast stream...');
      final stream = _eventChannel.receiveBroadcastStream();

      _logService.log('LiteRTService', 'Calling native sendMessageAsync...');
      await _channel.invokeMethod('sendMessageAsync', {
        'content': prompt,
        'systemInstruction': systemInstruction,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'cachePrompt': cachePrompt,
      });
      _logService.log('LiteRTService', 'Native sendMessageAsync called, waiting for stream events...');

      var tokenCount = 0;
      await for (final event in stream) {
        if (event is Map) {
          if (event['text'] != null) {
            tokenCount++;
            if (tokenCount % 50 == 0) {
              _logService.log('LiteRTService', 'Stream: $tokenCount tokens received');
            }
            yield event['text'] as String;
          } else if (event['error'] != null) {
            _logService.log('LiteRTService', 'ERROR from native: ${event['error']}');
            throw Exception(event['error']);
          } else if (event['done'] == true) {
            _logService.log('LiteRTService', 'Stream done signal received. Total tokens: $tokenCount');
            break;
          }
        }
      }
      _logService.log('LiteRTService', 'Streaming generation complete: $tokenCount tokens');
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Generation failed', e, null);
      throw Exception('Generation failed: ${e.message}');
    }
  }

  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    int maxTokens = 4096,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 10,
    bool cachePrompt = false,
  }) async {
    _logService.log('LiteRTService', '=== Starting non-streaming generation ===');
    _logService.log('LiteRTService', 'Prompt: "${prompt.length > 100 ? prompt.substring(0, 100) + "..." : prompt}" (${prompt.length} chars)');
    _logService.log('LiteRTService', 'System instruction: "${(systemInstruction ?? "").length > 100 ? (systemInstruction ?? "").substring(0, 100) + "..." : systemInstruction ?? ""}" (${(systemInstruction ?? "").length} chars)');
    _logService.log('LiteRTService', 'Params: maxTokens=$maxTokens, temp=$temperature, topP=$topP, topK=$topK, cachePrompt=$cachePrompt');

    if (!_isModelLoaded) {
      _logService.log('LiteRTService', 'ERROR: No model loaded');
      throw Exception('No model loaded. Load a model first.');
    }

    try {
      _logService.log('LiteRTService', 'Calling native sendMessage...');
      final result = await _channel.invokeMethod('sendMessage', {
        'content': prompt,
        'systemInstruction': systemInstruction,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'cachePrompt': cachePrompt,
      });
      final response = result as String;
      _logService.log('LiteRTService', 'Non-streaming response: ${response.length} chars');
      _logService.log('LiteRTService', 'Response preview: "${response.length > 100 ? response.substring(0, 100) + "..." : response}"');
      return response;
    } on PlatformException catch (e) {
      _logService.logError('LiteRTService', 'Generation failed', e, null);
      throw Exception('Generation failed: ${e.message}');
    }
  }

  Future<void> cancelGeneration() async {
    _logService.log('LiteRTService', 'Cancelling generation...');
    _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _channel.invokeMethod('cancel');
      _logService.log('LiteRTService', 'Generation cancelled');
    } on PlatformException {
      _logService.log('LiteRTService', 'Cancellation call failed (ignored)');
    }
  }

  void dispose() {
    _logService.log('LiteRTService', 'Disposing...');
    _streamSubscription?.cancel();
    unloadModel();
    _isInitialized = false;
    _logService.log('LiteRTService', 'Disposed');
  }
}
