import 'package:flutter/services.dart';
import '../services/log_service.dart';
import '../services/tflite_embedding_handler.dart';

class EmbeddingService {
  final LogService _logService;
  final TfliteEmbeddingHandler _handler;

  bool _isInitialized = false;
  int _embeddingDimension = 0;
  String? _currentModelPath;

  EmbeddingService({LogService? logService})
      : _logService = logService ?? LogService(),
        _handler = TfliteEmbeddingHandler(logService: logService);

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;
  String? get currentModelPath => _currentModelPath;

  Future<bool> initialize(String modelPath, {String? vocabPath}) async {
    try {
      _logService.log('EmbeddingService', 'Initializing with model: $modelPath');

      if (_isInitialized && _currentModelPath == modelPath) {
        _logService.log('EmbeddingService', 'Already initialized with this model');
        return true;
      }

      final success = await _handler.initialize(modelPath, vocabPath: vocabPath);
      _logService.log('EmbeddingService', 'Handler initialized: $success');

      _isInitialized = success;

      if (success) {
        _currentModelPath = modelPath;
        _embeddingDimension = _handler.embeddingDimension;
        _logService.log('EmbeddingService', 'Embedding dimension: $_embeddingDimension');
      }

      return _isInitialized;
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Exception initializing embedding', e, stackTrace);
      throw Exception('Failed to initialize embedding: $e');
    }
  }

  Future<int> getDimension() async {
    if (!_isInitialized) return 0;
    return _embeddingDimension;
  }

  Future<List<double>> embed(String text) async {
    if (!_isInitialized) {
      throw Exception('Embedding model not initialized');
    }

    try {
      final result = await _handler.embed(text);
      if (result == null) {
        throw Exception('Embedding returned null');
      }
      return result.toList();
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Failed to embed text', e, stackTrace);
      throw Exception('Failed to embed text: $e');
    }
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!_isInitialized) {
      throw Exception('Embedding model not initialized');
    }

    try {
      final results = await _handler.embedBatch(texts);
      return results
          .where((r) => r != null)
          .map((r) => r!.toList())
          .toList();
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Failed to embed batch', e, stackTrace);
      throw Exception('Failed to embed batch: $e');
    }
  }

  void dispose() {
    _handler.close();
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
  }
}
