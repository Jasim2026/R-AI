import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/embedding_model.dart';
import '../services/embedding_service.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';

class EmbeddingModelProvider extends ChangeNotifier {
  final EmbeddingService _embeddingService;
  final CacheService _cacheService;
  final LogService _logService;

  List<EmbeddingModel> _models = [];
  EmbeddingModel? _selectedModel;
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _error;

  EmbeddingModelProvider({
    required EmbeddingService embeddingService,
    required CacheService cacheService,
    LogService? logService,
  })  : _embeddingService = embeddingService,
        _cacheService = cacheService,
        _logService = logService ?? LogService();

  List<EmbeddingModel> get models => _models;
  EmbeddingModel? get selectedModel => _selectedModel;
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasModels => _models.isNotEmpty;
  int get embeddingDimension => _embeddingService.embeddingDimension;
  EmbeddingBackend? get activeBackend => _embeddingService.activeBackend;

  String get preferredBackend => 'tflite';

  Future<void> loadModels() async {
    _logService.log('EmbeddingModelProvider', 'Loading saved models...');
    final json = _cacheService.embeddingModelsJson;
    if (json != null && json.isNotEmpty) {
      try {
        final list = (jsonDecode(json) as List)
            .map((m) => EmbeddingModel.fromMap(m as Map<String, dynamic>))
            .toList();
        _models = list;
        _logService.log('EmbeddingModelProvider', 'Loaded ${_models.length} models from cache');
      } catch (e) {
        _logService.logError('EmbeddingModelProvider', 'Failed to parse cached models', e, null);
        _models = [];
      }
    } else {
      _logService.log('EmbeddingModelProvider', 'No cached models found');
    }

    final selectedId = _cacheService.selectedEmbeddingModelId;
    if (selectedId != null) {
      _selectedModel = _models.where((m) => m.id == selectedId).firstOrNull;
      _logService.log('EmbeddingModelProvider', 'Selected model ID: $selectedId -> ${_selectedModel?.name ?? "not found"}');
    }

    // Validate that model files still exist
    final beforeCount = _models.length;
    _models = _models.where((m) {
      final exists = File(m.path).existsSync();
      if (!exists) {
        _logService.log('EmbeddingModelProvider', 'Model file missing, removing: ${m.name} at ${m.path}');
      }
      return exists;
    }).toList();
    if (_models.length != beforeCount) {
      _logService.log('EmbeddingModelProvider', 'Removed ${beforeCount - _models.length} models with missing files');
    }

    if (_selectedModel != null && !File(_selectedModel!.path).existsSync()) {
      _logService.log('EmbeddingModelProvider', 'Selected model file missing, clearing selection');
      _selectedModel = null;
    }

    for (final m in _models) {
      _logService.log('EmbeddingModelProvider', '  Model: ${m.name} | id=${m.id} | dim=${m.dimensions} | vocab=${m.vocabPath != null ? "yes" : "no"} | path=${m.path}');
    }

    notifyListeners();
  }

  Future<void> _saveModels() async {
    final json = jsonEncode(_models.map((m) => m.toMap()).toList());
    await _cacheService.setEmbeddingModelsJson(json);
    _logService.log('EmbeddingModelProvider', 'Saved ${_models.length} models to cache');
  }

  /// Import a .zip file containing .tflite + vocab.txt
  Future<EmbeddingModel?> importZipModel() async {
    _logService.log('EmbeddingModelProvider', 'Importing ZIP model...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.isEmpty) {
        _logService.log('EmbeddingModelProvider', 'ZIP import cancelled by user');
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        _logService.log('EmbeddingModelProvider', 'ERROR: Selected file has no path');
        return null;
      }

      _logService.log('EmbeddingModelProvider', 'Selected ZIP: ${file.path} (${file.size} bytes)');
      _logService.log('EmbeddingModelProvider', 'Extracting ZIP...');
      final extracted = await EmbeddingService.extractZip(file.path!);

      if (extracted == null) {
        _logService.log('EmbeddingModelProvider', 'ERROR: Failed to extract ZIP');
        _error = 'Failed to extract zip. Ensure it contains a .tflite model file.';
        notifyListeners();
        return null;
      }

      final modelPath = extracted['model']!;
      final vocabPath = extracted['vocab'];
      _logService.log('EmbeddingModelProvider', 'ZIP extracted: model=$modelPath, vocab=${vocabPath ?? "none"}');

      // Validate extracted files
      if (!await File(modelPath).exists()) {
        _logService.log('EmbeddingModelProvider', 'ERROR: Extracted model file does not exist');
        _error = 'Extracted model file not found.';
        notifyListeners();
        return null;
      }
      final modelSize = await File(modelPath).length();
      _logService.log('EmbeddingModelProvider', 'Extracted model size: $modelSize bytes');

      if (vocabPath != null && await File(vocabPath).exists()) {
        final vocabSize = await File(vocabPath).length();
        _logService.log('EmbeddingModelProvider', 'Extracted vocab size: $vocabSize bytes');
      }

      final model = EmbeddingModel(
        name: file.name.replaceAll(RegExp(r'\.zip$'), ''),
        path: modelPath,
        vocabPath: vocabPath,
        description: vocabPath != null ? 'Imported from zip (model + vocab)' : 'Imported from zip (model only)',
      );

      _logService.log('EmbeddingModelProvider', 'Created model entry: ${model.name} (id=${model.id})');
      _models.add(model);
      await _saveModels();
      notifyListeners();

      return model;
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingModelProvider', 'Failed to import ZIP', e, stackTrace);
      _error = 'Failed to import zip: $e';
      notifyListeners();
      return null;
    }
  }

  /// Import individual files (.tflite model + optional vocab.txt)
  Future<EmbeddingModel?> importModel() async {
    _logService.log('EmbeddingModelProvider', 'Importing individual model file...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'litert', 'bin'],
      );

      if (result == null || result.files.isEmpty) {
        _logService.log('EmbeddingModelProvider', 'Model import cancelled by user');
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        _logService.log('EmbeddingModelProvider', 'ERROR: Selected file has no path');
        return null;
      }

      _logService.log('EmbeddingModelProvider', 'Selected model: ${file.path} (${file.size} bytes)');

      // Try to find vocab.txt in the same directory
      final modelFile = File(file.path!);
      final dir = modelFile.parent;
      _logService.log('EmbeddingModelProvider', 'Looking for vocab.txt in: ${dir.path}');
      String? vocabPath;
      final vocabFile = File('${dir.path}/vocab.txt');
      if (await vocabFile.exists()) {
        vocabPath = vocabFile.path;
        final vocabSize = await vocabFile.length();
        _logService.log('EmbeddingModelProvider', 'Found vocab.txt at: $vocabPath ($vocabSize bytes)');
      } else {
        _logService.log('EmbeddingModelProvider', 'No vocab.txt found in same directory');
      }

      final model = EmbeddingModel(
        name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        path: file.path!,
        vocabPath: vocabPath,
        description: vocabPath != null ? 'With vocab.txt' : 'No vocab.txt (Gemma backend only)',
      );

      _logService.log('EmbeddingModelProvider', 'Created model entry: ${model.name} (id=${model.id})');
      _models.add(model);
      await _saveModels();
      notifyListeners();

      return model;
    } catch (e, stackTrace) {
      _logService.logError('EmbeddingModelProvider', 'Failed to import model', e, stackTrace);
      _error = 'Failed to import model: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> loadModel(EmbeddingModel model) async {
    if (_isLoading) {
      _logService.log('EmbeddingModelProvider', 'loadModel called while already loading, ignoring');
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    _logService.log('EmbeddingModelProvider', '=== Loading embedding model: ${model.name} ===');
    _logService.log('EmbeddingModelProvider', 'Model ID: ${model.id}');
    _logService.log('EmbeddingModelProvider', 'Model path: ${model.path}');
    _logService.log('EmbeddingModelProvider', 'Vocab path: ${model.vocabPath ?? "none"}');
    _logService.log('EmbeddingModelProvider', 'Dimensions: ${model.dimensions}');

    try {
      // TFLite backend requires vocab.txt
      if (model.vocabPath == null || model.vocabPath!.isEmpty) {
        _logService.log('EmbeddingModelProvider', 'ERROR: No vocab.txt provided');
        _error = 'TFLite backend requires vocab.txt. '
            'Re-import with a zip containing both the .tflite model and vocab.txt.';
        _logService.log('EmbeddingModelProvider', 'ERROR: ${_error}');
        return false;
      }

      _logService.log('EmbeddingModelProvider', 'Loading model: ${model.name} from ${model.path}');

      final file = File(model.path);
      if (!await file.exists()) {
        _logService.log('EmbeddingModelProvider', 'ERROR: Model file not found: ${model.path}');
        _error = 'Model file not found: ${model.path}';
        _logService.log('EmbeddingModelProvider', 'ERROR: ${_error}');
        return false;
      }

      final fileSize = await file.length();
      _logService.log('EmbeddingModelProvider', 'Model file size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      if (model.vocabPath != null) {
        final vocabFile = File(model.vocabPath!);
        if (await vocabFile.exists()) {
          final vocabSize = await vocabFile.length();
          _logService.log('EmbeddingModelProvider', 'Vocab file size: $vocabSize bytes');
        } else {
          _logService.log('EmbeddingModelProvider', 'WARNING: Vocab file not found at ${model.vocabPath}');
        }
      }

      _logService.log('EmbeddingModelProvider', 'Calling EmbeddingService.initialize()...');
      final success = await _embeddingService.initialize(
        model.path,
        vocabPath: model.vocabPath,
      );
      _logService.log('EmbeddingModelProvider', 'EmbeddingService.initialize() returned: $success');

      _isLoaded = success;
      _selectedModel = model;

      if (success) {
        await _cacheService.setSelectedEmbeddingModelId(model.id);
        await _cacheService.setEmbeddingModelLoaded(true);

        final actualDim = _embeddingService.embeddingDimension;
        _logService.log('EmbeddingModelProvider', 'Model loaded successfully. Actual dimension: $actualDim');
        if (actualDim > 0 && actualDim != model.dimensions) {
          _logService.log('EmbeddingModelProvider', 'Dimension mismatch: expected ${model.dimensions}, got $actualDim. Updating...');
          final idx = _models.indexWhere((m) => m.id == model.id);
          if (idx >= 0) {
            _models[idx] = model.copyWith(dimensions: actualDim);
            await _saveModels();
          }
        }

        _logService.log('EmbeddingModelProvider', '=== Model loaded successfully: ${model.name} ===');
      } else {
        _error = 'Failed to load embedding model. '
            'Ensure the model file is valid and vocab.txt is present.';
        _logService.log('EmbeddingModelProvider', 'ERROR: ${_error}');
      }

      return success;
    } catch (e, stackTrace) {
      _isLoaded = false;
      _error = 'Error loading model: $e';
      _logService.logError('EmbeddingModelProvider', 'Exception loading model', e, stackTrace);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> unloadModel() async {
    _logService.log('EmbeddingModelProvider', 'Unloading embedding model...');
    _embeddingService.dispose();
    _isLoaded = false;
    await _cacheService.setEmbeddingModelLoaded(false);
    _logService.log('EmbeddingModelProvider', 'Model unloaded');
    notifyListeners();
  }

  Future<void> removeModel(String id) async {
    _logService.log('EmbeddingModelProvider', 'Removing model: $id');
    if (_selectedModel?.id == id) {
      _logService.log('EmbeddingModelProvider', 'Removing currently selected model, unloading first');
      await unloadModel();
      _selectedModel = null;
    }

    final model = _models.firstWhere((m) => m.id == id);
    _logService.log('EmbeddingModelProvider', 'Deleting model file: ${model.path}');
    try {
      final file = File(model.path);
      if (await file.exists()) {
        await file.delete();
        _logService.log('EmbeddingModelProvider', 'Model file deleted');
      }
      // Also delete vocab if it's in the same directory
      if (model.vocabPath != null) {
        final vocabFile = File(model.vocabPath!);
        if (await vocabFile.exists()) {
          await vocabFile.delete();
          _logService.log('EmbeddingModelProvider', 'Vocab file deleted');
        }
      }
    } catch (e) {
      _logService.logError('EmbeddingModelProvider', 'Error deleting model files', e, null);
    }

    _models.removeWhere((m) => m.id == id);
    await _saveModels();
    _logService.log('EmbeddingModelProvider', 'Model removed. Remaining models: ${_models.length}');
    notifyListeners();
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!_isLoaded) throw Exception('Embedding model not loaded');
    _logService.log('EmbeddingModelProvider', 'embedBatch: ${texts.length} texts');
    return await _embeddingService.embedBatch(texts);
  }

  Future<List<double>> embed(String text) async {
    if (!_isLoaded) throw Exception('Embedding model not loaded');
    _logService.log('EmbeddingModelProvider', 'embed: "${text.length > 50 ? text.substring(0, 50) + "..." : text}"');
    return await _embeddingService.embed(text);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
