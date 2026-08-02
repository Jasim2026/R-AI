import 'package:flutter/services.dart';

class EmbeddingService {
  static const MethodChannel _channel = MethodChannel('com.rai/embedding');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize(String modelPath) async {
    try {
      final result = await _channel.invokeMethod('initEmbedding', {
        'modelPath': modelPath,
      });
      _isInitialized = result as bool;
      return _isInitialized;
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize embedding: ${e.message}');
    }
  }

  Future<List<double>> embed(String text) async {
    if (!_isInitialized) {
      throw Exception('Embedding model not initialized');
    }

    try {
      final result = await _channel.invokeMethod('embed', {
        'text': text,
      });
      return List<double>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to embed text: ${e.message}');
    }
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!_isInitialized) {
      throw Exception('Embedding model not initialized');
    }

    try {
      final result = await _channel.invokeMethod('embedBatch', {
        'texts': texts,
      });
      return (result as List).map((e) => List<double>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('Failed to embed batch: ${e.message}');
    }
  }

  void dispose() {
    _channel.invokeMethod('closeEmbedding');
    _isInitialized = false;
  }
}
