import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'log_service.dart';

class GemmaEmbeddingHandler {
  EmbeddingModel? _model;
  bool _isInitialized = false;
  int _embeddingDimension = 768;

  final LogService _logService;

  GemmaEmbeddingHandler({LogService? logService})
      : _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;

  Future<bool> initialize(String modelPath) async {
    try {
      await close();

      _logService.log('GemmaEmbeddingHandler', 'Initializing with model: $modelPath');

      // Initialize the Gemma framework with embedding backend
      _logService.log('GemmaEmbeddingHandler', 'Initializing FlutterGemma...');
      await FlutterGemma.initialize(
        embeddingBackends: [LiteRtEmbeddingBackend()],
      );

      _logService.log('GemmaEmbeddingHandler', 'Creating embedding model...');
      _model = await FlutterGemma.instance.createEmbeddingModel(
        modelPath: modelPath,
      );

      if (_model == null) {
        _logService.log('GemmaEmbeddingHandler', 'ERROR: Failed to create embedding model');
        return false;
      }

      _logService.log('GemmaEmbeddingHandler', 'Running test embedding...');
      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _logService.log('GemmaEmbeddingHandler', 'Initialized successfully. Dimension: $_embeddingDimension');
        return true;
      } else {
        _logService.log('GemmaEmbeddingHandler', 'ERROR: Test embedding failed');
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('GemmaEmbeddingHandler', 'Error initializing Gemma handler', e, stackTrace);
      return false;
    }
  }

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized || _model == null) {
      _logService.log('GemmaEmbeddingHandler', 'ERROR: Not initialized');
      return null;
    }

    try {
      _logService.log('GemmaEmbeddingHandler', 'Embedding: "${text.substring(0, min(50, text.length))}..."');

      final result = await _model!.encode(text);
      if (result == null || result.isEmpty) {
        _logService.log('GemmaEmbeddingHandler', 'ERROR: encode returned null/empty');
        return null;
      }

      // L2 normalize
      var norm = 0.0;
      for (var i = 0; i < result.length; i++) {
        norm += result[i] * result[i];
      }
      norm = sqrt(norm);

      final embedding = Float32List(result.length);
      if (norm > 0) {
        for (var i = 0; i < result.length; i++) {
          embedding[i] = result[i] / norm;
        }
      } else {
        for (var i = 0; i < result.length; i++) {
          embedding[i] = result[i];
        }
      }

      _logService.log('GemmaEmbeddingHandler', 'Embedding successful. Dimension: ${embedding.length}');
      return embedding;
    } catch (e, stackTrace) {
      _logService.logError('GemmaEmbeddingHandler', 'Error during embedding', e, stackTrace);
      return null;
    }
  }

  Future<List<Float32List?>> embedBatch(List<String> texts) async {
    if (!_isInitialized || _model == null) {
      return List.filled(texts.length, null);
    }

    try {
      _logService.log('GemmaEmbeddingHandler', 'Batch embedding ${texts.length} texts...');
      final results = await _model!.batchEncode(texts);
      if (results == null) {
        return List.filled(texts.length, null);
      }

      return results.map((result) {
        if (result == null) return null;
        var norm = 0.0;
        for (var i = 0; i < result.length; i++) {
          norm += result[i] * result[i];
        }
        norm = sqrt(norm);
        final embedding = Float32List(result.length);
        if (norm > 0) {
          for (var i = 0; i < result.length; i++) {
            embedding[i] = result[i] / norm;
          }
        } else {
          for (var i = 0; i < result.length; i++) {
            embedding[i] = result[i];
          }
        }
        return embedding;
      }).toList();
    } catch (e, stackTrace) {
      _logService.logError('GemmaEmbeddingHandler', 'Error during batch embedding', e, stackTrace);
      return List.filled(texts.length, null);
    }
  }

  Future<void> close() async {
    _model?.dispose();
    _model = null;
    _isInitialized = false;
    _embeddingDimension = 768;
  }

  bool isReady() => _isInitialized;
}
