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
      _logService.log('TfliteEmbeddingHandler', 'Vocab path: ${vocabPath ?? "none"}');

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

      _logService.log('TfliteEmbeddingHandler', 'Loading vocabulary...');
      _vocab = await _loadVocab(vocabPath);
      if (_vocab == null || _vocab!.isEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'ERROR: Vocab file is empty or invalid: $vocabPath');
        return false;
      }
      _logService.log('TfliteEmbeddingHandler', 'Loaded vocab: ${_vocab!.length} entries');

      // Log some special tokens
      final clsToken = _vocab!['[CLS]'];
      final sepToken = _vocab!['[SEP]'];
      final unkToken = _vocab!['[UNK]'];
      _logService.log('TfliteEmbeddingHandler', 'Special tokens: [CLS]=$clsToken, [SEP]=$sepToken, [UNK]=$unkToken');

      final options = InterpreterOptions()..threads = 4;
      _logService.log('TfliteEmbeddingHandler', 'Interpreter options: threads=4');

      _logService.log('TfliteEmbeddingHandler', 'Creating interpreter...');
      _interpreter = await Interpreter.fromFile(File(modelPath), options: options);
      _logService.log('TfliteEmbeddingHandler', 'Interpreter created successfully');

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      _logService.log('TfliteEmbeddingHandler', 'Input tensors: ${inputTensors.length}');
      for (var tensor in inputTensors) {
        _logService.log('TfliteEmbeddingHandler', '  Input: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
      }

      // Check if model has a batch size > 1 and resize inputs to batch 1
      if (inputTensors.isNotEmpty) {
        final firstShape = inputTensors.first.shape;
        if (firstShape.length >= 2 && firstShape[0] > 1) {
          _logService.log('TfliteEmbeddingHandler', 'Model batch size ${firstShape[0]} > 1, resizing inputs to batch 1...');
          for (var i = 0; i < inputTensors.length; i++) {
            final tensor = inputTensors[i];
            final newShape = [1] + tensor.shape.sublist(1);
            _logService.log('TfliteEmbeddingHandler', '  Resizing ${tensor.name}: ${tensor.shape} -> $newShape');
            _interpreter!.resizeInputTensor(i, newShape);
          }
          _logService.log('TfliteEmbeddingHandler', 'Calling allocateTensors() after resize...');
          _interpreter!.allocateTensors();
          _logService.log('TfliteEmbeddingHandler', 'Tensors reallocated for batch size 1');
        }
      }

      // Re-read tensors after potential resize
      final inputTensorsAfter = _interpreter!.getInputTensors();
      final outputTensorsAfter = _interpreter!.getOutputTensors();

      _logService.log('TfliteEmbeddingHandler', 'Input tensors (after resize): ${inputTensorsAfter.length}');
      for (var tensor in inputTensorsAfter) {
        _logService.log('TfliteEmbeddingHandler', '  Input: ${tensor.name} shape=${tensor.shape} type=${tensor.type}');
      }

      _logService.log('TfliteEmbeddingHandler', 'Output tensors: ${outputTensorsAfter.length}');
      for (var tensor in outputTensorsAfter) {
        _logService.log('TfliteEmbeddingHandler', '  Output: ${tensor.name} shape=${tensor.shape} type=${tensor.type} scale=${tensor.params.scale} zeroPoint=${tensor.params.zeroPoint}');
        _outputType = tensor.type;
        _outputScale = tensor.params.scale;
        _outputZeroPoint = tensor.params.zeroPoint;
        _outputShape = List<int>.from(tensor.shape);
        if (tensor.shape.length >= 2) {
          _embeddingDimension = tensor.shape.last;
        }
      }

      _hasThreeInputs = inputTensorsAfter.length == 3;
      _logService.log('TfliteEmbeddingHandler', 'Model has ${inputTensorsAfter.length} inputs (3-input: $_hasThreeInputs)');

      if (inputTensorsAfter.isNotEmpty) {
        final inputShape = inputTensorsAfter.first.shape;
        if (inputShape.length >= 2) {
          _maxLength = inputShape[1];
        }
      }

      if (_embeddingDimension == 0) {
        _embeddingDimension = 384;
        _logService.log('TfliteEmbeddingHandler', 'Warning: Could not determine embedding dimension, defaulting to 384');
      }

      _logService.log('TfliteEmbeddingHandler', 'Output type: $_outputType, dim: $_embeddingDimension, maxLen: $_maxLength');
      _logService.log('TfliteEmbeddingHandler', 'Output shape: $_outputShape');

      _logService.log('TfliteEmbeddingHandler', 'Running test embedding...');
      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _logService.log('TfliteEmbeddingHandler', 'Test OK. Dimension: ${testResult.length}');
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _currentModelPath = modelPath;
        _logService.log('TfliteEmbeddingHandler', '=== Initialization successful ===');
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
    _logService.log('TfliteEmbeddingHandler', 'Loading vocab from: $path');
    final file = File(path);
    if (!await file.exists()) {
      _logService.log('TfliteEmbeddingHandler', 'Vocab file not found');
      return {};
    }
    final lines = await file.readAsLines();
    _logService.log('TfliteEmbeddingHandler', 'Vocab file: ${lines.length} lines');
    final vocab = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final word = lines[i].trim();
      if (word.isNotEmpty) {
        vocab[word] = i;
      }
    }
    _logService.log('TfliteEmbeddingHandler', 'Vocab loaded: ${vocab.length} entries');
    return vocab;
  }

  List<List<int>> tokenize(String text) {
    _logService.log('TfliteEmbeddingHandler', 'Tokenizing: "${text.length > 50 ? text.substring(0, 50) + "..." : text}"');
    final tokens = <int>[];
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    _logService.log('TfliteEmbeddingHandler', 'Words: ${words.length} -> ${words.take(5).join(", ")}${words.length > 5 ? "..." : ""}');

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

    _logService.log('TfliteEmbeddingHandler', 'Tokens: ${tokens.length} tokens, first 10: ${tokens.take(10).join(", ")}');
    _logService.log('TfliteEmbeddingHandler', 'Attention mask: ${attentionMask.where((e) => e == 1).length} ones out of ${attentionMask.length}');

    return [tokens, attentionMask, tokenTypeIds];
  }

  Object _createOutputBuffer() {
    _logService.log('TfliteEmbeddingHandler', 'Creating output buffer: type=$_outputType, dim=$_embeddingDimension');
    switch (_outputType) {
      case TensorType.float32:
        return List<List<double>>.generate(
          1,
          (_) => List<double>.filled(_embeddingDimension, 0.0),
        );
      case TensorType.float64:
        return List<List<double>>.generate(
          1,
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
          1,
          (_) => List<int>.filled(_embeddingDimension, 0),
        );
      case TensorType.float16:
        return List<List<int>>.generate(
          1,
          (_) => List<int>.filled(_embeddingDimension, 0),
        );
      default:
        _logService.log('TfliteEmbeddingHandler', 'WARNING: Unknown output type $_outputType, defaulting to float32 buffer');
        return List<List<double>>.generate(
          1,
          (_) => List<double>.filled(_embeddingDimension, 0.0),
        );
    }
  }

  Float32List _extractEmbedding(Object outputBuffer) {
    _logService.log('TfliteEmbeddingHandler', 'Extracting embedding from output buffer (type=$_outputType)');
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
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.uint8:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.int16:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.int32:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.int64:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.int4:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      case TensorType.uint16:
      case TensorType.uint32:
      case TensorType.uint64:
        final raw = (outputBuffer as List<List<int>>)[0];
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] = _outputScale * (raw[i] - _outputZeroPoint);
        }
        break;

      default:
        _logService.log('TfliteEmbeddingHandler', 'WARNING: Unsupported output type $_outputType, treating as float32');
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

    _logService.log('TfliteEmbeddingHandler', 'Embedding extracted: first 5 values: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}');
    return embedding;
  }

  static double _halfToFloat(int halfBits) {
    final sign = (halfBits >> 15) & 1;
    final exponent = (halfBits >> 10) & 0x1F;
    final mantissa = halfBits & 0x3FF;

    if (exponent == 0) {
      if (mantissa == 0) {
        return sign == 0 ? 0.0 : -0.0;
      }
      var value = mantissa / 1024.0;
      value *= pow(2, -14).toDouble();
      return sign == 0 ? value : -value;
    } else if (exponent == 31) {
      if (mantissa == 0) {
        return sign == 0 ? double.infinity : double.negativeInfinity;
      }
      return double.nan;
    }

    var value = 1.0 + mantissa / 1024.0;
    value *= pow(2, exponent - 15).toDouble();
    return sign == 0 ? value : -value;
  }

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized && _interpreter == null) {
      _logService.log('TfliteEmbeddingHandler', 'ERROR: Not initialized, cannot embed');
      return null;
    }

    try {
      _logService.log('TfliteEmbeddingHandler', 'Embedding: "${text.length > 50 ? text.substring(0, 50) + "..." : text}"');
      final tokenized = tokenize(text);
      final inputIds = tokenized[0];
      final attentionMask = tokenized[1];
      final tokenTypeIds = tokenized[2];

      _logService.log('TfliteEmbeddingHandler', 'Input IDs (first 10): ${inputIds.take(10).join(", ")}');
      _logService.log('TfliteEmbeddingHandler', 'Attention mask (first 10): ${attentionMask.take(10).join(", ")}');

      final outputBuffer = _createOutputBuffer();

      if (_hasThreeInputs) {
        final inputs = [
          [inputIds],
          [attentionMask],
          [tokenTypeIds],
        ];
        _logService.log('TfliteEmbeddingHandler', 'Running with 3 inputs, shapes: [1,${inputIds.length}], [1,${attentionMask.length}], [1,${tokenTypeIds.length}]');
        _interpreter!.runForMultipleInputs(inputs, {0: outputBuffer});
      } else {
        _logService.log('TfliteEmbeddingHandler', 'Running with 1 input, shape: [1,${inputIds.length}]');
        _interpreter!.run([inputIds], outputBuffer);
      }
      _logService.log('TfliteEmbeddingHandler', 'Inference completed');

      final embedding = _extractEmbedding(outputBuffer);

      var norm = 0.0;
      for (var i = 0; i < _embeddingDimension; i++) {
        norm += embedding[i] * embedding[i];
      }
      norm = sqrt(norm);
      _logService.log('TfliteEmbeddingHandler', 'L2 norm before normalization: ${norm.toStringAsFixed(6)}');

      if (norm > 0) {
        for (var i = 0; i < _embeddingDimension; i++) {
          embedding[i] /= norm;
        }
      }

      _logService.log('TfliteEmbeddingHandler', 'Embedding complete: dim=${embedding.length}, first 5: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}');
      return embedding;
    } catch (e, stackTrace) {
      _logService.logError('TfliteEmbeddingHandler', 'Error during embedding', e, stackTrace);
      return null;
    }
  }

  Future<List<Float32List?>> embedBatch(List<String> texts) async {
    _logService.log('TfliteEmbeddingHandler', 'Embedding batch: ${texts.length} texts');
    final results = <Float32List?>[];
    for (var i = 0; i < texts.length; i++) {
      _logService.log('TfliteEmbeddingHandler', 'Batch item ${i + 1}/${texts.length}');
      results.add(await embed(texts[i]));
    }
    final successCount = results.where((r) => r != null).length;
    _logService.log('TfliteEmbeddingHandler', 'Batch complete: $successCount/${texts.length} successful');
    return results;
  }

  Future<void> close() async {
    _logService.log('TfliteEmbeddingHandler', 'Closing handler...');
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _embeddingDimension = 0;
    _currentModelPath = null;
    _hasThreeInputs = false;
    _vocab = null;
    _outputType = TensorType.float32;
    _outputScale = 1.0;
    _outputZeroPoint = 0;
    _logService.log('TfliteEmbeddingHandler', 'Handler closed');
  }

  bool isReady() => _isInitialized;
}
