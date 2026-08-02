import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../services/log_service.dart';
import '../services/tflite_embedding_handler.dart';
import '../services/gemma_embedding_handler.dart';

enum EmbeddingBackend { tflite, gemma }

class EmbeddingService {
  final LogService _logService;
  final TfliteEmbeddingHandler _tfliteHandler;
  final GemmaEmbeddingHandler _gemmaHandler;

  bool _isInitialized = false;
  int _embeddingDimension = 0;
  String? _currentModelPath;
  EmbeddingBackend? _activeBackend;
  String? _vocabPath;

  EmbeddingService({LogService? logService})
      : _logService = logService ?? LogService(),
        _tfliteHandler = TfliteEmbeddingHandler(logService: logService),
        _gemmaHandler = GemmaEmbeddingHandler(logService: logService);

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;
  String? get currentModelPath => _currentModelPath;
  EmbeddingBackend? get activeBackend => _activeBackend;

  /// Extract a zip file containing .tflite + vocab.txt to internal storage.
  /// Returns { 'model': '/path/to/model.tflite', 'vocab': '/path/to/vocab.txt' }
  static Future<Map<String, String>?> extractZip(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final appDir = await getApplicationDocumentsDirectory();
      final extractDir = Directory('${appDir.path}/embedding_models/${DateTime.now().millisecondsSinceEpoch}');
      await extractDir.create(recursive: true);

      String? modelPath;
      String? vocabPath;

      for (final entry in archive) {
        if (entry.isFile) {
          final fileName = entry.name.split('/').last.toLowerCase();
          final outPath = '${extractDir.path}/$fileName';
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);

          if (fileName.endsWith('.tflite') || fileName.endsWith('.litert') || fileName.endsWith('.bin')) {
            modelPath = outPath;
          } else if (fileName == 'vocab.txt' || fileName.endsWith('_vocab.txt')) {
            vocabPath = outPath;
          }
        }
      }

      if (modelPath != null) {
        return {
          'model': modelPath,
          if (vocabPath != null) 'vocab': vocabPath,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> initialize(
    String modelPath, {
    String? vocabPath,
    EmbeddingBackend? preferredBackend,
  }) async {
    try {
      _logService.log('EmbeddingService', 'Initializing with model: $modelPath');

      if (_isInitialized && _currentModelPath == modelPath) {
        _logService.log('EmbeddingService', 'Already initialized with this model');
        return true;
      }

      await dispose();

      final backend = preferredBackend ?? EmbeddingBackend.tflite;
      bool success = false;

      // Try preferred backend first
      if (backend == EmbeddingBackend.gemma) {
        _logService.log('EmbeddingService', 'Trying Gemma backend...');
        success = await _gemmaHandler.initialize(modelPath);
        if (success) {
          _activeBackend = EmbeddingBackend.gemma;
        }
      }

      if (!success && backend == EmbeddingBackend.gemma) {
        // Gemma failed, don't fallback to tflite — user explicitly chose Gemma
        _logService.log('EmbeddingService', 'Gemma backend failed. '
            'Switch to TFLite backend in Settings if you have a compatible model + vocab.txt.');
        _activeBackend = null;
        return false;
      }

      if (!success && backend == EmbeddingBackend.tflite) {
        _logService.log('EmbeddingService', 'Trying TFLite backend...');
        success = await _tfliteHandler.initialize(modelPath, vocabPath: vocabPath);
        if (success) {
          _activeBackend = EmbeddingBackend.tflite;
        }
      }

      if (!success && backend == EmbeddingBackend.tflite) {
        // TFLite failed, try Gemma as fallback
        _logService.log('EmbeddingService', 'TFLite failed, trying Gemma as fallback...');
        success = await _gemmaHandler.initialize(modelPath);
        if (success) {
          _activeBackend = EmbeddingBackend.gemma;
          _logService.log('EmbeddingService', 'Fallback to Gemma succeeded');
        }
      }

      _logService.log('EmbeddingService', 'Backend init result: $success, active: $_activeBackend');

      _isInitialized = success;

      if (success) {
        _currentModelPath = modelPath;
        _vocabPath = vocabPath;
        _embeddingDimension = _activeBackend == EmbeddingBackend.gemma
            ? _gemmaHandler.embeddingDimension
            : _tfliteHandler.embeddingDimension;
        _logService.log('EmbeddingService', 'Embedding dimension: $_embeddingDimension, backend: $_activeBackend');
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
      Float32List? result;
      if (_activeBackend == EmbeddingBackend.gemma) {
        result = await _gemmaHandler.embed(text);
      } else {
        result = await _tfliteHandler.embed(text);
      }

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
      List<Float32List?> results;
      if (_activeBackend == EmbeddingBackend.gemma) {
        results = await _gemmaHandler.embedBatch(texts);
      } else {
        results = await _tfliteHandler.embedBatch(texts);
      }

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
    _tfliteHandler.close();
    _gemmaHandler.close();
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _activeBackend = null;
    _vocabPath = null;
  }
}
