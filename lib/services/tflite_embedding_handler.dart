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
  int _modelBatchSize = 1;
  String? _currentModelPath;
  bool _hasThreeInputs = false;
  Map<String, int>? _vocab;

  TensorType _outputType = TensorType.float32;
  double _outputScale = 1.0;
  int _outputZeroPoint = 0;
  List<int> _outputShape = [1, 384];

  final LogService _logService;

  TfliteEmbeddingHandler({LogService? logService})
      : _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;

  Future<bool> initialize(String modelPath, {String? vocabPath}) async {
    _logService.log('TfliteEmbeddingHandler', '=== Initializing TFLite embedding handler ===');
    try {
      await close();

      _logService.log('TfliteEmbeddingHandler', 'Model path: $modelPath');

      final file = File(modelPath);
      if (!await file.exists()) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Model file not found: $modelPath');
        return false;
      }

      final fileSize = await file.length();
      _logService.log('TfliteEmbeddingHandler', 'Model file size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      if (vocabPath == null || vocabPath.isEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: No vocab.txt provided');
        return false;
      }

      final vocabFile = File(vocabPath);
      if (!await vocabFile.exists()) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Vocab file not found: $vocabPath');
        return false;
      }

      _vocab = await _loadVocab(vocabPath);
      if (_vocab == null || _vocab!.isEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Vocab is empty or invalid');
        return false;
      }
      _logService.log('TfliteEmbeddingHandler', 'Loaded vocab: ${_vocab!.length} entries');

      final options = InterpreterOptions()..threads = 4;

      _logService.log('TfliteEmbeddingHandler', 'Creating interpreter...');
      _interpreter = await Interpreter.fromFile(File(modelPath), options: options);
      _logService.log('TfliteEmbeddingHandler', 'Interpreter created');

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      _logService.log('TfliteEmbeddingHandler', 'Input tensors: ${inputTensors.length}');
      for (var tensor in inputTensors) {
        _logService.log('TfliteEmbeddingHandler', '  Input: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
      }

      // Detect batch size — do NOT resize, we will pad inputs instead
      if (inputTensors.isNotEmpty) {
        final firstShape = inputTensors.first.shape;
        _modelBatchSize = firstShape.length >= 2 ? firstShape[0] : 1;
        _maxLength = firstShape.length >= 2 ? firstShape[1] : 128;
      }
      _logService.log('TfliteEmbeddingHandler', 'Model batch size: $_modelBatchSize, maxLen: $_maxLength');

      _hasThreeInputs = inputTensors.length == 3;
      _logService.log('TfliteEmbeddingHandler', '3-input model: $_hasThreeInputs');

      _logService.log('TfliteEmbeddingHandler', 'Output tensors: ${outputTensors.length}');
      for (var tensor in outputTensors) {
        _logService.log('TfliteEmbeddingHandler', '  Output: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
        _outputType = tensor.type;
        _outputScale = tensor.params.scale;
        _outputZeroPoint = tensor.params.zeroPoint;
        _outputShape = List<int>.from(tensor.shape);
        if (tensor.shape.length >= 2) {
          _embeddingDimension = tensor.shape.last;
        }
      }

      if (_embeddingDimension == 0) {
        _embeddingDimension = 384;
      }

      _logService.log('TfliteEmbeddingHandler', 'Output type: $_outputType, dim: $_embeddingDimension');

      _logService.log('TfliteEmbeddingHandler', 'Running test embedding...');
      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _currentModelPath = modelPath;
        _logService.log('TfliteEmbeddingHandler', '=== Init OK. Dim: $_embeddingDimension ===');
        return true;
      } else {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Test embedding failed');
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('TfliteEmbeddingHandler', 'Error initializing', e, stackTrace);
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

    tokens.add(_vocab!['[CLS]'] ?? 101);

    for (var word in words) {
      if (word.isEmpty) continue;
      if (tokens.length >= _maxLength - 1) break;

      if (_vocab!.containsKey(word)) {
        tokens.add(_vocab![word]!);
      } else {
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

    tokens.add(_vocab!['[SEP]'] ?? 102);

    final attentionMask = List<int>.filled(_maxLength, 0);
    for (var i = 0; i < tokens.length && i < _maxLength; i++) {
      attentionMask[i] = 1;
    }

    final tokenTypeIds = List<int>.filled(_maxLength, 0);

    while (tokens.length < _maxLength) {
      tokens.insert(tokens.length - 1, 0);
    }

    return [tokens, attentionMask, tokenTypeIds];
  }

  List<List<int>> _padToBatch(List<int> singleRow) {
    if (_modelBatchSize <= 1) return [singleRow];
    return List<List<int>>.generate(_modelBatchSize, (_) => List<int>.from(singleRow));
  }

  Object _createOutputBuffer() {
    switch (_outputType) {
      case TensorType.float32:
        return List<List<double>>.generate(
          _modelBatchSize,
          (_) => List<double>.filled(_embeddingDimension, 0.0),
        );
      case TensorType.float64:
        return List<List<double>>.generate(
          _modelBatchSize,
          (_) => List<double>.filled(_embeddingDimension, 0.0),
        );
      case TensorType.int8:
      case TensorType.uint8:
      case TensorType.int16:
      case TensorType.int32:
      case TensorType.int64:
      case TensorType.int4:
      case TensorType.uint16:
      case TensorType.uint32:
      case TensorType.uint64:
        return List<List<int>>.generate(
          _modelBatchSize,
          (_) => List<int>.filled(_embeddingDimension, 0),
        );
      case TensorType.float16:
        return List<List<int>>.generate(
          _modelBatchSize,
          (_) => List<int>.filled(_embeddingDimension, 0),
        );
      default:
        return List<List<double>>.generate(
          _modelBatchSize,
          (_) => List<double>.filled(_embeddingDimension, 0.0),
        );
    }
  }

  Float32List _extractEmbedding(Object outputBuffer) {
    final embedding = Float32List(_embeddingDimension);

    switch (_outputType) {
      case TensorType.float32:
        final raw = (outputBuffer as List<List<double>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = raw[i];
        }
        break;

      case TensorType.float64:
        final raw = (outputBuffer as List<List<double>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = raw[i];
        }
        break;

      case TensorType.float16:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _halfToFloat(raw[i]);
        }
        break;

      case TensorType.int8:
      case TensorType.uint8:
      case TensorType.int16:
      case TensorType.int32:
      case TensorType.int64:
      case TensorType.int4:
      case TensorType.uint16:
      case TensorType.uint32:
      case TensorType.uint64:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      default:
        try {
          final raw = outputBuffer as List<List<double>>;
          for (var i = 0; i < _embeddingDimension; i++) {
            embedding[i] = raw[0][i];
          }
        } catch (_) {
          final raw = (outputBuffer as List<List<int>>)[0];
          for (var i = 0; i < _embeddingDimension; i++) {
            embedding[i] = raw[i].toDouble();
          }
        }
    }

    return embedding;
  }

  static double _halfToFloat(int halfBits) {
    final sign = (halfBits >> 15) & 1;
    final exponent = (halfBits >> 10) & 0x1F;
    final mantissa = halfBits & 0x3FF;

    if (exponent == 0) {
      if (mantissa == 0) return sign == 0 ? 0.0 : -0.0;
      var value = mantissa / 1024.0;
      value *= pow(2, -14).toDouble();
      return sign == 0 ? value : -value;
    } else if (exponent == 31) {
      if (mantissa == 0) return sign == 0 ? double.infinity : double.negativeInfinity;
      return double.nan;
    }

    var value = 1.0 + mantissa / 1024.0;
    value *= pow(2, exponent - 15).toDouble();
    return sign == 0 ? value : -value;
  }

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized && _interpreter == null) return null;

    try {
      final tokenized = tokenize(text);
      final inputIds = tokenized[0];
      final attentionMask = tokenized[1];
      final tokenTypeIds = tokenized[2];

      final outputBuffer = _createOutputBuffer();

      if (_hasThreeInputs) {
        final inputs = [
          _padToBatch(inputIds),
          _padToBatch(attentionMask),
          _padToBatch(tokenTypeIds),
        ];
        _interpreter!.runForMultipleInputs(inputs, {0: outputBuffer});
      } else {
        _interpreter!.run(_padToBatch(inputIds), outputBuffer);
      }

      final embedding = _extractEmbedding(outputBuffer);

      var norm = 0.0;
      for (var i = 0; i < _embeddingDimension; i++) {
        norm += embedding[i] * embedding[i];
      }
      norm = sqrt(norm);
      if (norm > 0) {
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] /= norm;
        }
      }

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
    _modelBatchSize = 1;
    _currentModelPath = null;
    _hasThreeInputs = false;
    _vocab = null;
    _outputType = TensorType.float32;
    _outputScale = 1.0;
    _outputZeroPoint = 0;
  }

  bool isReady() => _isInitialized;
}
