import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../services/log_service.dart';
import '../services/tflite_embedding_handler.dart';

enum EmbeddingBackend { tflite }

class EmbeddingService {
  final LogService _logService;
  final TfliteEmbeddingHandler _tfliteHandler;

  bool _isInitialized = false;
  int _embeddingDimension = 0;
  String? _currentModelPath;
  EmbeddingBackend? _activeBackend;
  String? _vocabPath;

  EmbeddingService({LogService? logService})
      : _logService = logService ?? LogService(),
        _tfliteHandler = TfliteEmbeddingHandler(logService: logService);

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;
  String? get currentModelPath => _currentModelPath;
  EmbeddingBackend? get activeBackend => _activeBackend;

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

      await disposeAsync();

      _logService.log('EmbeddingService', 'Initializing TFLite backend...');
      final success = await _tfliteHandler.initialize(modelPath, vocabPath: vocabPath);

      if (success) {
        _activeBackend = EmbeddingBackend.tflite;
        _currentModelPath = modelPath;
        _vocabPath = vocabPath;
        _embeddingDimension = _tfliteHandler.embeddingDimension;
        _isInitialized = true;
        _logService.log('EmbeddingService', 'Dimension: $_embeddingDimension');
      } else {
        _activeBackend = null;
        _logService.log('EmbeddingService', 'Initialization failed');
      }

      return _isInitialized;
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Exception initializing embedding', e, stackTrace);
      throw Exception('Failed to initialize embedding: $e');
    }
  }

  Future<List<double>> embed(String text) async {
    if (!_isInitialized) {
      throw Exception('Embedding model not initialized');
    }

    try {
      final result = await _tfliteHandler.embed(text);
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
      final results = await _tfliteHandler.embedBatch(texts);
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
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _activeBackend = null;
    _vocabPath = null;
  }

  Future<void> disposeAsync() async {
    await _tfliteHandler.close();
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _activeBackend = null;
    _vocabPath = null;
  }
}
