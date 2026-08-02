import 'dart:async';
import 'package:flutter/services.dart';
import '../models/llm_model.dart';

class LiteRTService {
  static const MethodChannel _channel = MethodChannel('com.rai/litert');
  static const EventChannel _eventChannel = EventChannel('com.rai/litert_stream');

  bool _isInitialized = false;
  bool _isModelLoaded = false;
  LLMModel? _currentModel;
  StreamSubscription? _streamSubscription;

  bool get isInitialized => _isInitialized;
  bool get isModelLoaded => _isModelLoaded;
  LLMModel? get currentModel => _currentModel;

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      _isInitialized = true;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize LiteRT: ${e.message}');
    }
  }

  Future<void> loadModel(LLMModel model) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      await _channel.invokeMethod('loadModel', {
        'modelPath': model.path,
        'backend': model.backendName,
        'cacheDir': model.cacheDir,
      });
      _currentModel = model;
      _isModelLoaded = true;
    } on PlatformException catch (e) {
      throw Exception('Failed to load model: ${e.message}');
    }
  }

  Future<void> unloadModel() async {
    if (!_isModelLoaded) return;

    _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _channel.invokeMethod('unloadModel');
      _currentModel = null;
      _isModelLoaded = false;
    } on PlatformException catch (e) {
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
    if (!_isModelLoaded) {
      throw Exception('No model loaded. Load a model first.');
    }

    try {
      final stream = _eventChannel.receiveBroadcastStream();

      await _channel.invokeMethod('sendMessageAsync', {
        'content': prompt,
        'systemInstruction': systemInstruction,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'cachePrompt': cachePrompt,
      });

      await for (final event in stream) {
        if (event is Map) {
          if (event['text'] != null) {
            yield event['text'] as String;
          } else if (event['error'] != null) {
            throw Exception(event['error']);
          } else if (event['done'] == true) {
            break;
          }
        }
      }
    } on PlatformException catch (e) {
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
    if (!_isModelLoaded) {
      throw Exception('No model loaded. Load a model first.');
    }

    try {
      final result = await _channel.invokeMethod('sendMessage', {
        'content': prompt,
        'systemInstruction': systemInstruction,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'cachePrompt': cachePrompt,
      });
      return result as String;
    } on PlatformException catch (e) {
      throw Exception('Generation failed: ${e.message}');
    }
  }

  Future<void> cancelGeneration() async {
    _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _channel.invokeMethod('cancel');
    } on PlatformException {
      // Ignore cancellation errors
    }
  }

  void dispose() {
    _streamSubscription?.cancel();
    unloadModel();
    _isInitialized = false;
  }
}