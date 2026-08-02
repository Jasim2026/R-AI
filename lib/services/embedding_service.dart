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
    final logService = LogService();
    logService.log('EmbeddingService', 'Extracting ZIP: $zipPath');
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        logService.log('EmbeddingService', 'ERROR: ZIP file not found: $zipPath');
        return null;
      }
      final zipSize = await zipFile.length();
      logService.log('EmbeddingService', 'ZIP file size: $zipSize bytes');

      final bytes = await zipFile.readAsBytes();
      logService.log('EmbeddingService', 'Read ${bytes.length} bytes, decoding...');
      final archive = ZipDecoder().decodeBytes(bytes);
      logService.log('EmbeddingService', 'ZIP decoded: ${archive.length} entries');

      final appDir = await getApplicationDocumentsDirectory();
      final extractDir = Directory('${appDir.path}/embedding_models/${DateTime.now().millisecondsSinceEpoch}');
      await extractDir.create(recursive: true);
      logService.log('EmbeddingService', 'Extracting to: ${extractDir.path}');

      String? modelPath;
      String? vocabPath;

      for (final entry in archive) {
        if (entry.isFile) {
          final fileName = entry.name.split('/').last.toLowerCase();
          final outPath = '${extractDir.path}/$fileName';
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);

          final entrySize = (entry.content as List<int>).length;
          logService.log('EmbeddingService', '  Extracted: $fileName ($entrySize bytes)');

          if (fileName.endsWith('.tflite') || fileName.endsWith('.litert') || fileName.endsWith('.bin')) {
            modelPath = outPath;
            logService.log('EmbeddingService', '  -> Model file detected: $outPath');
          } else if (fileName == 'vocab.txt' || fileName.endsWith('_vocab.txt')) {
            vocabPath = outPath;
            logService.log('EmbeddingService', '  -> Vocab file detected: $outPath');
          }
        }
      }

      if (modelPath != null) {
        logService.log('EmbeddingService', 'ZIP extraction successful: model=$modelPath, vocab=${vocabPath ?? "none"}');
        return {
          'model': modelPath,
          if (vocabPath != null) 'vocab': vocabPath,
        };
      }
      logService.log('EmbeddingService', 'ERROR: No model file found in ZIP');
      return null;
    } catch (e, stackTrace) {
      logService.logError('EmbeddingService', 'Failed to extract ZIP', e, stackTrace);
      return null;
    }
  }

  Future<bool> initialize(
    String modelPath, {
    String? vocabPath,
    EmbeddingBackend? preferredBackend,
  }) async {
    _logService.log('EmbeddingService', '=== Initializing embedding service ===');
    _logService.log('EmbeddingService', 'Model: $modelPath');
    _logService.log('EmbeddingService', 'Vocab: ${vocabPath ?? "none"}');
    _logService.log('EmbeddingService', 'Backend: ${preferredBackend?.name ?? "auto"}');

    try {
      if (_isInitialized && _currentModelPath == modelPath) {
        _logService.log('EmbeddingService', 'Already initialized with this model, skipping');
        return true;
      }

      _logService.log('EmbeddingService', 'Disposing previous handler...');
      await disposeAsync();

      _logService.log('EmbeddingService', 'Initializing TFLite backend...');
      final success = await _tfliteHandler.initialize(modelPath, vocabPath: vocabPath);

      if (success) {
        _activeBackend = EmbeddingBackend.tflite;
        _currentModelPath = modelPath;
        _vocabPath = vocabPath;
        _embeddingDimension = _tfliteHandler.embeddingDimension;
        _isInitialized = true;
        _logService.log('EmbeddingService', '=== Initialization successful ===');
        _logService.log('EmbeddingService', 'Backend: tflite');
        _logService.log('EmbeddingService', 'Dimension: $_embeddingDimension');
      } else {
        _activeBackend = null;
        _logService.log('EmbeddingService', '=== Initialization FAILED ===');
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

    _logService.log('EmbeddingService', 'Embedding: "${text.length > 80 ? text.substring(0, 80) + "..." : text}"');
    try {
      final result = await _tfliteHandler.embed(text);
      if (result == null) {
        _logService.log('EmbeddingService', 'ERROR: Embedding returned null');
        throw Exception('Embedding returned null');
      }
      _logService.log('EmbeddingService', 'Embedding OK: dim=${result.length}, first 5 values: ${result.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}');
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

    _logService.log('EmbeddingService', 'Embedding batch: ${texts.length} texts');
    try {
      final results = await _tfliteHandler.embedBatch(texts);
      final validResults = results
          .where((r) => r != null)
          .map((r) => r!.toList())
          .toList();
      _logService.log('EmbeddingService', 'Batch embedding complete: ${validResults.length}/${texts.length} successful');
      if (validResults.isNotEmpty) {
        _logService.log('EmbeddingService', 'First vector dim: ${validResults.first.length}');
      }
      return validResults;
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingService', 'Failed to embed batch', e, stackTrace);
      throw Exception('Failed to embed batch: $e');
    }
  }

  void dispose() {
    _logService.log('EmbeddingService', 'Disposing (sync)...');
    _tfliteHandler.close();
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _activeBackend = null;
    _vocabPath = null;
  }

  Future<void> disposeAsync() async {
    _logService.log('EmbeddingService', 'Disposing (async)...');
    await _tfliteHandler.close();
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _activeBackend = null;
    _vocabPath = null;
  }
}
