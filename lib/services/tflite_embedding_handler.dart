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
        // Get embedding dimension from output tensor
        if (tensor.shape.length >= 2) {
          _embeddingDimension = tensor.shape.last;
        }
      }

      if (_embeddingDimension == 0) {
        // Fallback: try to infer from model input
        if (inputTensors.isNotEmpty) {
          final inputShape = inputTensors.first.shape;
          if (inputShape.length >= 2) {
            _maxLength = inputShape[1];
          }
        }
        // Default dimension for all-MiniLM-L6-v2
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

  List<int> tokenize(String text) {
    // Simple BERT WordPiece tokenizer
    // This is a basic implementation - for production, use a proper tokenizer
    final tokens = <int>[];
    final words = text.toLowerCase().split(RegExp(r'\s+'));

    // Basic vocabulary - common tokens for English
    // In production, load from tokenizer.json file
    final vocab = _getBasicVocab();

    tokens.add(vocab['[CLS]'] ?? 101);
    tokens.add(vocab['[SEP]'] ?? 102);

    for (var word in words) {
      if (tokens.length >= _maxLength - 1) break;

      // Try whole word first
      if (vocab.containsKey(word)) {
        tokens.insert(tokens.length - 1, vocab[word]!);
      } else {
        // Basic wordpiece: split into subwords
        var remaining = word;
        var isFirst = true;

        while (remaining.isNotEmpty && tokens.length < _maxLength - 1) {
          var found = false;
          for (var end = remaining.length; end > 0; end--) {
            var subword = remaining.substring(0, end);
            if (!isFirst) subword = '##$subword';

            if (vocab.containsKey(subword)) {
              tokens.insert(tokens.length - 1, vocab[subword]!);
              remaining = remaining.substring(end);
              isFirst = false;
              found = true;
              break;
            }
          }
          if (!found) {
            // Unknown token
            tokens.insert(tokens.length - 1, vocab['[UNK]'] ?? 100);
            remaining = '';
          }
        }
      }
    }

    // Pad to max length
    while (tokens.length < _maxLength) {
      tokens.insert(tokens.length - 1, vocab['[PAD]'] ?? 0);
    }

    return tokens;
  }

  Map<String, int> _getBasicVocab() {
    // Basic vocabulary for demonstration
    // In production, load from tokenizer.json or vocab.txt file
    return {
      '[PAD]': 0,
      '[UNK]': 100,
      '[CLS]': 101,
      '[SEP]': 102,
      '[MASK]': 103,
      'the': 1996,
      'a': 1037,
      'an': 2019,
      'is': 2003,
      'are': 2024,
      'was': 2001,
      'were': 2020,
      'be': 2022,
      'been': 2042,
      'being': 2108,
      'have': 2031,
      'has': 2038,
      'had': 2041,
      'do': 2052,
      'does': 2528,
      'did': 2106,
      'will': 2097,
      'would': 2052,
      'could': 2071,
      'should': 2323,
      'may': 2089,
      'might': 2454,
      'shall': 2323,
      'can': 2064,
      'need': 2342,
      'i': 1045,
      'me': 2033,
      'my': 2026,
      'mine': 2026,
      'you': 2017,
      'your': 2115,
      'he': 2002,
      'him': 2002,
      'his': 2011,
      'she': 2016,
      'her': 2016,
      'it': 2009,
      'its': 2009,
      'we': 2057,
      'us': 2149,
      'our': 2256,
      'they': 2027,
      'them': 2068,
      'their': 2037,
      'what': 2054,
      'which': 2029,
      'who': 2040,
      'whom': 2040,
      'this': 2023,
      'that': 2008,
      'these': 2122,
      'those': 2008,
      'not': 2025,
      'no': 2053,
      'but': 2021,
      'if': 2065,
      'or': 2030,
      'and': 1998,
      'so': 2061,
      'just': 2074,
      'than': 2084,
      'more': 2062,
      'also': 2036,
      'very': 2061,
      'often': 2160,
      'however': 2116,
      'too': 2055,
      'quite': 3243,
      'since': 2116,
      'until': 2127,
      'while': 2096,
    };
  }

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized || _interpreter == null) {
      _logService.log('TfliteEmbeddingHandler', 'ERROR: Not initialized');
      return null;
    }

    try {
      _logService.log('TfliteEmbeddingHandler', 'Tokenizing text: "${text.substring(0, min(50, text.length))}..."');

      final tokens = tokenize(text);
      _logService.log('TfliteEmbeddingHandler', 'Tokens length: ${tokens.length}');

      // Create attention mask (1 for real tokens, 0 for padding)
      final attentionMask = Int32List(_maxLength);
      for (var i = 0; i < _maxLength; i++) {
        attentionMask[i] = tokens[i] != 0 ? 1 : 0;
      }

      // Create input tensor [1, maxLength]
      final input = [tokens];
      final mask = [attentionMask.toList()];

      // Create output tensor [1, embeddingDimension]
      final output = List.filled(1 * _embeddingDimension, 0.0).reshape([1, _embeddingDimension]);

      // Run inference
      _logService.log('TfliteEmbeddingHandler', 'Running inference...');
      _interpreter!.run(input, output);

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
    return Future.wait(texts.map((text) => embed(text)));
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
  }

  bool isReady() => _isInitialized;
}
