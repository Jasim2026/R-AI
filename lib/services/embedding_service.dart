import 'package:flutter/services.dart';
import '../services/log_service.dart';

class EmbeddingService {
  static const MethodChannel _channel = MethodChannel('com.rai/embedding');
  final LogService _logService;

  bool _isInitialized = false;
  int _embeddingDimension = 0;
  String? _currentModelPath;

  EmbeddingService({LogService? logService})
      : _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;
  String? get currentModelPath => _currentModelPath;

  Future<bool> initialize(String modelPath) async {
    try {
      _logService.log('EmbeddingService', 'Initializing with model: $modelPath');

      if (_isInitialized && _currentModelPath == modelPath) {
        _logService.log('EmbeddingService', 'Already initialized with this model');
        return true;
      }

      final result = await _channel.invokeMethod('initEmbedding', {
        'modelPath': modelPath,
      });
      _isInitialized = result as bool;

      _logService.log('EmbeddingService', 'initEmbedding returned: $_isInitialized');

      if (_isInitialized) {
        _currentModelPath = modelPath;
        _embeddingDimension = await getDimension();
        _logService.log('EmbeddingService', 'Embedding dimension: $_embeddingDimension');
      }

      return _isInitialized;
    } on PlatformException catch (e) {
      _logService.logError('EmbeddingService', 'PlatformException initializing embedding', e, null);
      throw Exception('Failed to initialize embedding: ${e.message}');
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Exception initializing embedding', e, stackTrace);
      throw Exception('Failed to initialize embedding: $e');
    }
  }

  Future<int> getDimension() async {
    if (!_isInitialized) return 0;

    try {
      final result = await _channel.invokeMethod('getEmbeddingDimension');
      _embeddingDimension = result as int;
      return _embeddingDimension;
    } on PlatformException catch (e) {
      _logService.logError('EmbeddingService', 'Failed to get dimension', e, null);
      throw Exception('Failed to get embedding dimension: ${e.message}');
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
      _logService.logError('EmbeddingService', 'Failed to embed text', e, null);
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
      _logService.logError('EmbeddingService', 'Failed to embed batch', e, null);
      throw Exception('Failed to embed batch: ${e.message}');
    }
  }

  void dispose() {
    _channel.invokeMethod('closeEmbedding');
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
  }
}
