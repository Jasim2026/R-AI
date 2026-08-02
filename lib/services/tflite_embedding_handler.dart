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

  final LogService _logService;

  TfliteEmbeddingHandler({LogService? logService})
      : _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;

  Future<bool> initialize(String modelPath) async {
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

      final options = InterpreterOptions()..threads = 4;

      _logService.log('TfliteEmbeddingHandler', 'Creating interpreter from file...');
      _interpreter = await Interpreter.fromFile(modelPath, options: options);
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

      // Detect if model has 3 inputs (BERT-style) or 1 input
      _hasThreeInputs = inputTensors.length == 3;
      _logService.log('TfliteEmbeddingHandler', 'Model has ${inputTensors.length} inputs (3-input BERT: $_hasThreeInputs)');

      // Get max sequence length from first input
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
      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'Test embedding successful. Actual dimension: ${testResult.length}');
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _currentModelPath = modelPath;
        return true;
      } else {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Test embedding failed');
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('TfliteEmbeddingHandler', 'Error initializing TFLite handler', e, stackTrace);
      return false;
    }
  }

  /// Tokenize text for BERT model
  /// Returns [inputIds, attentionMask, tokenTypeIds]
  List<List<int>> tokenize(String text) {
    final tokens = <int>[];
    final words = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').split(RegExp(r'\s+'));

    // Add [CLS] token
    tokens.add(101);

    for (var word in words) {
      if (word.isEmpty) continue;
      if (tokens.length >= _maxLength - 1) break;

      // Simple character-level tokenization for demonstration
      // For production, load proper tokenizer.json from model
      for (var i = 0; i < word.length && tokens.length < _maxLength - 1; i++) {
        tokens.add(_charToId(word[i]));
      }
    }

    // Add [SEP] token
    tokens.add(102);

    // Create attention mask (1 for real tokens, 0 for padding)
    final attentionMask = List<int>.filled(_maxLength, 0);
    for (var i = 0; i < tokens.length && i < _maxLength; i++) {
      attentionMask[i] = 1;
    }

    // Create token type IDs (0 for all tokens in single sentence)
    final tokenTypeIds = List<int>.filled(_maxLength, 0);

    // Pad tokens to max length
    while (tokens.length < _maxLength) {
      tokens.insert(tokens.length - 1, 0); // Insert before [SEP]
    }

    return [tokens, attentionMask, tokenTypeIds];
  }

  int _charToId(String char) {
    // Map common characters to IDs
    // For production, use proper tokenizer vocabulary
    if (char == ' ') return 1037; // 'a' space-like
    if (RegExp(r'[0-9]').hasMatch(char)) return 48 + int.parse(char);
    if (RegExp(r'[a-z]').hasMatch(char)) return 97 + (char.codeUnitAt(0) - 97);
    if (RegExp(r'[A-Z]').hasMatch(char)) return 65 + (char.codeUnitAt(0) - 65);
    return 100; // [UNK]
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

      // Create output tensor as nested list [1, embeddingDimension]
      final output = List.generate(1, (_) => List<double>.filled(_embeddingDimension, 0.0));

      // Run inference based on model input count
      _logService.log('TfliteEmbeddingHandler', 'Running inference...');
      if (_hasThreeInputs) {
        // BERT-style model: input_ids, attention_mask, token_type_ids
        final inputs = [
          [inputIds],
          [attentionMask],
          [tokenTypeIds],
        ];
        _interpreter!.runForMultipleInputs(inputs, {0: output});
      } else {
        // Single input model
        _interpreter!.run([inputIds], output);
      }

      // Get embedding and normalize
      final embedding = Float32List(_embeddingDimension);
      var norm = 0.0;
      for (var i = 0; i < _embeddingDimension; i++) {
        embedding[i] = output[0][i];
        norm += embedding[i] * embedding[i];
      }
      norm = sqrt(norm);

      // L2 normalize
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
  }

  bool isReady() => _isInitialized;
}
