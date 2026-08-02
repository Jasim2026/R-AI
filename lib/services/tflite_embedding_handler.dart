import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'log_service.dart';

class TfliteEmbeddingHandler {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  int _embeddingDimension = 0;
  int _maxLength = 128;
  String? _currentModelPath;
  bool _hasThreeInputs = false;
  Map<String, int>? _vocab;

  final LogService _logService;

  TfliteEmbeddingHandler({LogService? logService})
      : _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;

  Future<bool> initialize(String modelPath, {String? vocabPath}) async {
    try {
      await close();

      _logService.log('TfliteEmbeddingHandler', 'Initializing with model: $modelPath');

      final file = File(modelPath);
      if (!await file.exists()) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Model file not found: $modelPath');
        return false;
      }

      final fileSize = await file.length();
      _logService.log('TfliteEmbeddingHandler', 'Model file size: $fileSize bytes');

      // Load vocabulary — REQUIRED for correct tokenization
      if (vocabPath == null || vocabPath.isEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: No vocab.txt provided. '
            'TFLite embedding requires a vocab.txt file matching the model. '
            'Import a .zip containing both the .tflite model and vocab.txt, '
            'or import vocab.txt separately.');
        return false;
      }

      final vocabFile = File(vocabPath);
      if (!await vocabFile.exists()) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Vocab file not found: $vocabPath');
        return false;
      }

      _vocab = await _loadVocab(vocabPath);
      if (_vocab == null || _vocab!.isEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Vocab file is empty or invalid: $vocabPath');
        return false;
      }
      _logService.log('TfliteEmbeddingHandler', 'Loaded vocab: ${_vocab!.length} entries');

      final options = InterpreterOptions()..threads = 4;

      _logService.log('TfliteEmbeddingHandler', 'Creating interpreter from file...');
      _interpreter = await Interpreter.fromFile(File(modelPath), options: options);
      _logService.log('TfliteEmbeddingHandler', 'Interpreter created successfully');

      _logService.log('TfliteEmbeddingHandler', 'Getting input/output tensors...');
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      _logService.log('TfliteEmbeddingHandler', 'Input tensors: ${inputTensors.length}');
      for (var tensor in inputTensors) {
        _logService.log('TfliteEmbeddingHandler', '  Input: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
      }

      _logService.log('TfliteEmbeddingHandler', 'Output tensors: ${outputTensors.length}');
      for (var tensor in outputTensors) {
        _logService.log('TfliteEmbeddingHandler', '  Output: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
        if (tensor.shape.length >= 2) {
          _embeddingDimension = tensor.shape.last;
        }
      }

      _hasThreeInputs = inputTensors.length == 3;
      _logService.log('TfliteEmbeddingHandler', 'Model has ${inputTensors.length} inputs (3-input BERT: $_hasThreeInputs)');

      if (inputTensors.isNotEmpty) {
        final inputShape = inputTensors.first.shape;
        if (inputShape.length >= 2) {
          _maxLength = inputShape[1];
        }
      }

      if (_embeddingDimension == 0) {
        _embeddingDimension = 384;
      }

      _logService.log('TfliteEmbeddingHandler', 'Embedding dimension: $_embeddingDimension');
      _logService.log('TfliteEmbeddingHandler', 'Max sequence length: $_maxLength');

      // Run test embedding
      _logService.log('TfliteEmbeddingHandler', 'Running test embedding...');
      _logService.log('TfliteEmbeddingHandler', 'Vocab size: ${_vocab?.length ?? 0}');
      _logService.log('TfliteEmbeddingHandler', 'Max length: $_maxLength, Has 3 inputs: $_hasThreeInputs');
      _logService.log('TfliteEmbeddingHandler', 'Embedding dim: $_embeddingDimension');

      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'Test embedding successful. Actual dimension: ${testResult.length}');
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _currentModelPath = modelPath;
        return true;
      } else {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Test embedding failed - result was ${testResult == null ? "null" : "empty (length ${testResult.length})"}');
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('TfliteEmbeddingHandler', 'Error initializing TFLite handler', e, stackTrace);
      return false;
    }
  }

  Future<Map<String, int>> _loadVocab(String path) async {
    final file = File(path);
    if (!await file.exists()) return {};
    final lines = await file.readAsLines();
    final vocab = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final word = lines[i].trim();
      if (word.isNotEmpty) {
        vocab[word] = i;
      }
    }
    return vocab;
  }

  List<List<int>> tokenize(String text) {
    final tokens = <int>[];
    final words = text.toLowerCase().split(RegExp(r'\s+'));

    // [CLS] token
    tokens.add(_vocab!['[CLS]'] ?? 101);

    for (var word in words) {
      if (word.isEmpty) continue;
      if (tokens.length >= _maxLength - 1) break;

      // Try whole word first
      if (_vocab!.containsKey(word)) {
        tokens.add(_vocab![word]!);
      } else {
        // WordPiece tokenization
        var start = 0;
        while (start < word.length && tokens.length < _maxLength - 1) {
          var end = word.length;
          var found = false;
          while (start < end) {
            var sub = word.substring(start, end);
            if (start > 0) sub = '##$sub';
            if (_vocab!.containsKey(sub)) {
              tokens.add(_vocab![sub]!);
              start = end;
              found = true;
              break;
            }
            end--;
          }
          if (!found) {
            tokens.add(_vocab!['[UNK]'] ?? 100);
            start = word.length;
          }
        }
      }
    }

    // [SEP] token
    tokens.add(_vocab!['[SEP]'] ?? 102);

    // Attention mask
    final attentionMask = List<int>.filled(_maxLength, 0);
    for (var i = 0; i < tokens.length && i < _maxLength; i++) {
      attentionMask[i] = 1;
    }

    // Token type IDs
    final tokenTypeIds = List<int>.filled(_maxLength, 0);

    // Pad tokens to max length
    while (tokens.length < _maxLength) {
      tokens.insert(tokens.length - 1, 0);
    }

    return [tokens, attentionMask, tokenTypeIds];
  }

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized || _interpreter == null) {
      _logService.log('TfliteEmbeddingHandler', 'ERROR: Not initialized');
      return null;
    }

    try {
      _logService.log('TfliteEmbeddingHandler', 'Tokenizing text: "${text.substring(0, min(50, text.length))}..."');

      final tokenized = tokenize(text);
      final inputIds = tokenized[0];
      final attentionMask = tokenized[1];
      final tokenTypeIds = tokenized[2];

      _logService.log('TfliteEmbeddingHandler', 'Tokens length: ${inputIds.length}');

      final output = List<List<double>>.generate(
        1,
        (_) => List<double>.filled(_embeddingDimension, 0.0),
      );

      _logService.log('TfliteEmbeddingHandler', 'Running inference...');
      try {
        if (_hasThreeInputs) {
          final inputs = [
            [inputIds],
            [attentionMask],
            [tokenTypeIds],
          ];
          _logService.log('TfliteEmbeddingHandler', 'Input shapes: ${inputs.map((e) => (e as List).length > 0 ? (e[0] as List).length : 0).toList()}');
          _logService.log('TfliteEmbeddingHandler', 'Output shape: [${output.length}, ${output[0].length}]');
          _interpreter!.runForMultipleInputs(inputs, {0: output});
        } else {
          _interpreter!.run([inputIds], output);
        }
        _logService.log('TfliteEmbeddingHandler', 'Inference completed');
      } catch (e, st) {
        _logService.logError('TfliteEmbeddingHandler', 'Inference FAILED', e, st);
        return null;
      }

      // Get embedding and L2 normalize
      final embedding = Float32List(_embeddingDimension);
      var norm = 0.0;
      for (var i = 0; i < _embeddingDimension; i++) {
        embedding[i] = (output[0][i] as num).toDouble();
        norm += embedding[i] * embedding[i];
      }
      norm = sqrt(norm);

      if (norm > 0) {
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] /= norm;
        }
      }

      _logService.log('TfliteEmbeddingHandler', 'Embedding successful. Dimension: ${embedding.length}');
      return embedding;
    } catch (e, stackTrace) {
      _logService.logError('TfliteEmbeddingHandler', 'Error during embedding', e, stackTrace);
      return null;
    }
  }

  Future<List<Float32List?>> embedBatch(List<String> texts) async {
    final results = <Float32List?>[];
    for (var text in texts) {
      results.add(await embed(text));
    }
    return results;
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _hasThreeInputs = false;
    _vocab = null;
  }

  bool isReady() => _isInitialized;
}
