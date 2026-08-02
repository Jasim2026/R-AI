import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'log_service.dart';

final _logService = LogService();

// ── TFLite C API type definitions ──

typedef TfLiteModelCreateFromFileNative = Pointer<Void> Function(Pointer<Utf8>);
typedef TfLiteModelCreateFromFileDart = Pointer<Void> Function(Pointer<Utf8>);

typedef TfLiteInterpreterCreateNative = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef TfLiteInterpreterCreateDart = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);

typedef TfLiteInterpreterDeleteNative = Void Function(Pointer<Void>);
typedef TfLiteInterpreterDeleteDart = void Function(Pointer<Void>);

typedef TfLiteModelDeleteNative = Void Function(Pointer<Void>);
typedef TfLiteModelDeleteDart = void Function(Pointer<Void>);

typedef TfLiteInterpreterGetInputTensorCountNative = Int32 Function(Pointer<Void>);
typedef TfLiteInterpreterGetInputTensorCountDart = int Function(Pointer<Void>);

typedef TfLiteInterpreterGetOutputTensorCountNative = Int32 Function(Pointer<Void>);
typedef TfLiteInterpreterGetOutputTensorCountDart = int Function(Pointer<Void>);

typedef TfLiteInterpreterGetInputTensorNative = Pointer<Void> Function(Pointer<Void>, Int32);
typedef TfLiteInterpreterGetInputTensorDart = Pointer<Void> Function(Pointer<Void>, int);

typedef TfLiteInterpreterGetOutputTensorNative = Pointer<Void> Function(Pointer<Void>, Int32);
typedef TfLiteInterpreterGetOutputTensorDart = Pointer<Void> Function(Pointer<Void>, int);

typedef TfLiteTensorByteSizeNative = int Function(Pointer<Void>);
typedef TfLiteTensorByteSizeDart = int Function(Pointer<Void>);

typedef TfLiteTensorTypeNative = Int32 Function(Pointer<Void>);
typedef TfLiteTensorTypeDart = int Function(Pointer<Void>);

typedef TfLiteTensorNumDimsNative = Int32 Function(Pointer<Void>);
typedef TfLiteTensorNumDimsDart = int Function(Pointer<Void>);

typedef TfLiteTensorDimNative = Int32 Function(Pointer<Void>, Int32);
typedef TfLiteTensorDimDart = int Function(Pointer<Void>, int);

typedef TfLiteInterpreterResizeInputTensorNative = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>, Int32);
typedef TfLiteInterpreterResizeInputTensorDart = int Function(Pointer<Void>, int, Pointer<Int32>, int);

typedef TfLiteInterpreterAllocateTensorsNative = Int32 Function(Pointer<Void>);
typedef TfLiteInterpreterAllocateTensorsDart = int Function(Pointer<Void>);

typedef TfLiteTensorCopyFromBufferNative = Int32 Function(Pointer<Void>, Pointer<Void>, int);
typedef TfLiteTensorCopyFromBufferDart = int Function(Pointer<Void>, Pointer<Void>, int);

typedef TfLiteTensorCopyToBufferNative = Int32 Function(Pointer<Void>, Pointer<Void>, int);
typedef TfLiteTensorCopyToBufferDart = int Function(Pointer<Void>, Pointer<Void>, int);

typedef TfLiteInterpreterInvokeNative = Int32 Function(Pointer<Void>);
typedef TfLiteInterpreterInvokeDart = int Function(Pointer<Void>);

// TfLiteStatus enum values
const int _kTfLiteOk = 0;

// TfLiteType enum values
const int _kTfLiteFloat32 = 1;
const int _kTfLiteInt32 = 2;
const int _kTfLiteUInt8 = 3;
const int _kTfLiteInt64 = 4;
const int _kTfLiteString = 5;
const int _kTfLiteBool = 6;
const int _kTfLiteInt16 = 7;
const int _kTfLiteDouble = 8;
const int _kTfLiteInt4 = 9;
const int _kTfLiteUInt16 = 10;
const int _kTfLiteUInt32 = 11;
const int _kTfLiteUInt64 = 12;

class TfliteFfiHandler {
  DynamicLibrary? _lib;
  Pointer<Void>? _model;
  Pointer<Void>? _interpreter;
  bool _isInitialized = false;
  int _embeddingDimension = 0;
  int _maxLength = 128;
  int _modelBatchSize = 1;
  bool _hasThreeInputs = false;
  Map<String, int>? _vocab;
  List<int> _inputTensorShape = [];
  List<int> _outputTensorShape = [];

  bool get isInitialized => _isInitialized;
  int get embeddingDimension => _embeddingDimension;

  Future<bool> initialize(String modelPath, {String? vocabPath}) async {
    _logService.log('TfliteFfi', '=== Initializing TFLite FFI handler ===');
    try {
      await close();

      _logService.log('TfliteFfi', 'Model path: $modelPath');

      // Load vocab
      if (vocabPath == null || vocabPath.isEmpty) {
        _logService.log('TfliteFfi', 'ERROR: No vocab.txt provided');
        return false;
      }
      final vocabFile = File(vocabPath);
      if (!await vocabFile.exists()) {
        _logService.log('TfliteFfi', 'ERROR: Vocab file not found: $vocabPath');
        return false;
      }
      _vocab = await _loadVocab(vocabPath);
      if (_vocab == null || _vocab!.isEmpty) {
        _logService.log('TfliteFfi', 'ERROR: Vocab is empty');
        return false;
      }
      _logService.log('TfliteFfi', 'Vocab loaded: ${_vocab!.length} entries');

      // Load native library
      _logService.log('TfliteFfi', 'Loading native library...');
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libtensorflowlite_c.so');
      } else if (Platform.isLinux) {
        _lib = DynamicLibrary.open('libtensorflowlite_c.so');
      } else if (Platform.isMacOS) {
        _lib = DynamicLibrary.open('libtensorflowlite_c.dylib');
      } else if (Platform.isWindows) {
        _lib = DynamicLibrary.open('tensorflowlite_c.dll');
      }
      _logService.log('TfliteFfi', 'Native library loaded');

      // Look up functions
      final createModelFromFile = _lib!.lookupFunction<TfLiteModelCreateFromFileDart, TfLiteModelCreateFromFileNative>('TfLiteModelCreateFromFile');
      final createInterpreter = _lib!.lookupFunction<TfLiteInterpreterCreateDart, TfLiteInterpreterCreateNative>('TfLiteInterpreterCreate');
      final deleteModel = _lib!.lookupFunction<TfLiteModelDeleteDart, TfLiteModelDeleteNative>('TfLiteModelDelete');
      final getInputTensorCount = _lib!.lookupFunction<TfLiteInterpreterGetInputTensorCountDart, TfLiteInterpreterGetInputTensorCountNative>('TfLiteInterpreterGetInputTensorCount');
      final getOutputTensorCount = _lib!.lookupFunction<TfLiteInterpreterGetOutputTensorCountDart, TfLiteInterpreterGetOutputTensorCountNative>('TfLiteInterpreterGetOutputTensorCount');
      final getInputTensor = _lib!.lookupFunction<TfLiteInterpreterGetInputTensorDart, TfLiteInterpreterGetInputTensorNative>('TfLiteInterpreterGetInputTensor');
      final getOutputTensor = _lib!.lookupFunction<TfLiteInterpreterGetOutputTensorDart, TfLiteInterpreterGetOutputTensorNative>('TfLiteInterpreterGetOutputTensor');
      final tensorNumDims = _lib!.lookupFunction<TfLiteTensorNumDimsDart, TfLiteTensorNumDimsNative>('TfLiteTensorNumDims');
      final tensorDim = _lib!.lookupFunction<TfLiteTensorDimDart, TfLiteTensorDimNative>('TfLiteTensorDim');
      final tensorByteSize = _lib!.lookupFunction<TfLiteTensorByteSizeDart, TfLiteTensorByteSizeNative>('TfLiteTensorByteSize');
      final tensorType = _lib!.lookupFunction<TfLiteTensorTypeDart, TfLiteTensorTypeNative>('TfLiteTensorType');
      final resizeInputTensor = _lib!.lookupFunction<TfLiteInterpreterResizeInputTensorDart, TfLiteInterpreterResizeInputTensorNative>('TfLiteInterpreterResizeInputTensor');
      final allocateTensors = _lib!.lookupFunction<TfLiteInterpreterAllocateTensorsDart, TfLiteInterpreterAllocateTensorsNative>('TfLiteInterpreterAllocateTensors');
      final tensorCopyFromBuffer = _lib!.lookupFunction<TfLiteTensorCopyFromBufferDart, TfLiteTensorCopyFromBufferNative>('TfLiteTensorCopyFromBuffer');
      final tensorCopyToBuffer = _lib!.lookupFunction<TfLiteTensorCopyToBufferDart, TfLiteTensorCopyToBufferNative>('TfLiteTensorCopyToBuffer');
      final invoke = _lib!.lookupFunction<TfLiteInterpreterInvokeDart, TfLiteInterpreterInvokeNative>('TfLiteInterpreterInvoke');
      final deleteInterpreter = _lib!.lookupFunction<TfLiteInterpreterDeleteDart, TfLiteInterpreterDeleteNative>('TfLiteInterpreterDelete');

      // Load model
      _logService.log('TfliteFfi', 'Loading model from file...');
      final modelPathC = modelPath.toNativeUtf8();
      _model = createModelFromFile(modelPathC);
      calloc.free(modelPathC);
      if (_model == nullptr) {
        _logService.log('TfliteFfi', 'ERROR: Failed to load model');
        return false;
      }
      _logService.log('TfliteFfi', 'Model loaded');

      // Create interpreter
      _logService.log('TfliteFfi', 'Creating interpreter...');
      _interpreter = createInterpreter(_model!, nullptr);
      if (_interpreter == nullptr) {
        _logService.log('TfliteFfi', 'ERROR: Failed to create interpreter');
        deleteModel(_model!);
        _model = nullptr;
        return false;
      }
      _logService.log('TfliteFfi', 'Interpreter created');

      // Read input tensors
      final inputCount = getInputTensorCount(_interpreter!);
      _logService.log('TfliteFfi', 'Input tensors: $inputCount');
      _hasThreeInputs = inputCount == 3;

      for (var i = 0; i < inputCount; i++) {
        final tensor = getInputTensor(_interpreter!, i);
        final numDims = tensorNumDims(tensor);
        final shape = <int>[];
        for (var d = 0; d < numDims; d++) {
          shape.add(tensorDim(tensor, d));
        }
        final type = tensorType(tensor);
        final size = tensorByteSize(tensor);
        _logService.log('TfliteFfi', '  Input[$i]: shape=$shape type=$type size=$size bytes');
        if (i == 0) _inputTensorShape = shape;
      }

      // Detect batch size
      if (_inputTensorShape.length >= 2) {
        _modelBatchSize = _inputTensorShape[0];
        _maxLength = _inputTensorShape[1];
      }
      _logService.log('TfliteFfi', 'Model batch size: $_modelBatchSize, max length: $_maxLength');

      // Resize all inputs to batch size 1
      _logService.log('TfliteFfi', 'Resizing inputs to batch 1...');
      for (var i = 0; i < inputCount; i++) {
        final newShape = calloc<Int32>(_inputTensorShape.length);
        newShape[0] = 1;
        for (var d = 1; d < _inputTensorShape.length; d++) {
          newShape[d] = _inputTensorShape[d];
        }
        final status = resizeInputTensor(_interpreter!, i, newShape, _inputTensorShape.length);
        calloc.free(newShape);
        if (status != _kTfLiteOk) {
          _logService.log('TfliteFfi', 'ERROR: resizeInputTensor failed for input $i with status $status');
          // Continue anyway - try allocateTensors
        }
      }

      // Allocate tensors
      _logService.log('TfliteFfi', 'Allocating tensors...');
      final allocStatus = allocateTensors(_interpreter!);
      _logService.log('TfliteFfi', 'allocateTensors status: $allocStatus');
      if (allocStatus != _kTfLiteOk) {
        _logService.log('TfliteFfi', 'WARNING: allocateTensors returned non-OK status, trying to continue...');
      }

      // Read output tensors
      final outputCount = getOutputTensorCount(_interpreter!);
      _logService.log('TfliteFfi', 'Output tensors: $outputCount');
      for (var i = 0; i < outputCount; i++) {
        final tensor = getOutputTensor(_interpreter!, i);
        final numDims = tensorNumDims(tensor);
        final shape = <int>[];
        for (var d = 0; d < numDims; d++) {
          shape.add(tensorDim(tensor, d));
        }
        final type = tensorType(tensor);
        _logService.log('TfliteFfi', '  Output[$i]: shape=$shape type=$type');
        _outputTensorShape = shape;
        if (shape.length >= 2) {
          _embeddingDimension = shape.last;
        }
      }

      _logService.log('TfliteFfi', 'Output dim: $_embeddingDimension');

      // Test embedding
      _logService.log('TfliteFfi', 'Running test embedding...');
      final testResult = await embed('test');
      if (testResult != null && testResult.isNotEmpty) {
        _embeddingDimension = testResult.length;
        _isInitialized = true;
        _logService.log('TfliteFfi', '=== Initialization successful ===');
        return true;
      } else {
        _logService.log('TfliteFfi', 'ERROR: Test embedding failed');
        return false;
      }
    } catch (e, stackTrace) {
      _logService.logError('TfliteFfi', 'Error initializing', e, stackTrace);
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

  Future<Float32List?> embed(String text) async {
    if (!_isInitialized || _interpreter == null) return null;

    try {
      final tokenized = tokenize(text);
      final inputIds = tokenized[0];
      final attentionMask = tokenized[1];
      final tokenTypeIds = tokenized[2];

      // Look up functions
      final getInputTensor = _lib!.lookupFunction<TfLiteInterpreterGetInputTensorDart, TfLiteInterpreterGetInputTensorNative>('TfLiteInterpreterGetInputTensor');
      final tensorCopyFromBuffer = _lib!.lookupFunction<TfLiteTensorCopyFromBufferDart, TfLiteTensorCopyFromBufferNative>('TfLiteTensorCopyFromBuffer');
      final tensorByteSize = _lib!.lookupFunction<TfLiteTensorByteSizeDart, TfLiteTensorByteSizeNative>('TfLiteTensorByteSize');
      final getOutputTensor = _lib!.lookupFunction<TfLiteInterpreterGetOutputTensorDart, TfLiteInterpreterGetOutputTensorNative>('TfLiteInterpreterGetOutputTensor');
      final tensorCopyToBuffer = _lib!.lookupFunction<TfLiteTensorCopyToBufferDart, TfLiteTensorCopyToBufferNative>('TfLiteTensorCopyToBuffer');
      final invoke = _lib!.lookupFunction<TfLiteInterpreterInvokeDart, TfLiteInterpreterInvokeNative>('TfLiteInterpreterInvoke');

      // Copy inputs to tensors
      final inputs = [inputIds, attentionMask, tokenTypeIds];
      for (var i = 0; i < inputs.length; i++) {
        final tensor = getInputTensor(_interpreter!, i);
        final expectedSize = tensorByteSize(tensor);

        // Create int32 buffer matching the model's batch size
        final int32List = Int32List(_modelBatchSize * _maxLength);
        // Fill first row with our data, rest are zeros (padding)
        for (var j = 0; j < inputs[i].length && j < _maxLength; j++) {
          int32List[j] = inputs[i][j];
        }

        final ptr = calloc.allocate<Int8>(expectedSize, alignment: 4);
        final byteData = ptr.asTypedList(expectedSize);
        final srcBytes = int32List.buffer.asUint8List();
        for (var b = 0; b < expectedSize && b < srcBytes.length; b++) {
          byteData[b] = srcBytes[b];
        }

        final status = tensorCopyFromBuffer(tensor, ptr.cast(), expectedSize);
        calloc.free(ptr);

        if (status != _kTfLiteOk) {
          _logService.log('TfliteFfi', 'WARNING: tensorCopyFromBuffer failed for input $i (status=$status, expectedSize=$expectedSize)');
        }
      }

      // Run inference
      final invokeStatus = invoke(_interpreter!);
      if (invokeStatus != _kTfLiteOk) {
        _logService.log('TfliteFfi', 'ERROR: invoke failed with status $invokeStatus');
        return null;
      }

      // Read output
      final outputTensor = getOutputTensor(_interpreter!, 0);
      final outputByteSize = tensorByteSize(outputTensor);
      final outputPtr = calloc.allocate<Int8>(outputByteSize, alignment: 4);

      final copyStatus = tensorCopyToBuffer(outputTensor, outputPtr.cast(), outputByteSize);
      if (copyStatus != _kTfLiteOk) {
        _logService.log('TfliteFfi', 'ERROR: tensorCopyToBuffer failed');
        calloc.free(outputPtr);
        return null;
      }

      // Extract first row from output (batch index 0)
      final outputFloats = Float32List.view(outputPtr.cast<Uint8>().buffer, 0, outputByteSize ~/ 4);
      final embedding = Float32List(_embeddingDimension);
      for (var i = 0; i < _embeddingDimension; i++) {
        embedding[i] = outputFloats[i];
      }
      calloc.free(outputPtr);

      // L2 normalize
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
      _logService.logError('TfliteFfi', 'Error during embedding', e, stackTrace);
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
    if (_interpreter != null) {
      try {
        final deleteInterpreter = _lib!.lookupFunction<TfLiteInterpreterDeleteDart, TfLiteInterpreterDeleteNative>('TfLiteInterpreterDelete');
        deleteInterpreter(_interpreter!);
      } catch (_) {}
      _interpreter = null;
    }
    if (_model != null) {
      try {
        final deleteModel = _lib!.lookupFunction<TfLiteModelDeleteDart, TfLiteModelDeleteNative>('TfLiteModelDelete');
        deleteModel(_model!);
      } catch (_) {}
      _model = null;
    }
    _lib = null;
    _isInitialized = false;
    _embeddingDimension = 0;
    _modelBatchSize = 1;
    _vocab = null;
  }

  bool isReady() => _isInitialized;
}
