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

  Future<void> loadModels() async {
    final json = _cacheService.embeddingModelsJson;
    if (json != null && json.isNotEmpty) {
      try {
        final list = (jsonDecode(json) as List)
            .map((m) => EmbeddingModel.fromMap(m as Map<String, dynamic>))
            .toList();
        _models = list;
      } catch (_) {
        _models = [];
      }
    }

    final selectedId = _cacheService.selectedEmbeddingModelId;
    if (selectedId != null) {
      _selectedModel = _models.where((m) => m.id == selectedId).firstOrNull;
    }

    // Validate that model files still exist
    _models = _models.where((m) => File(m.path).existsSync()).toList();
    if (_selectedModel != null && !File(_selectedModel!.path).existsSync()) {
      _selectedModel = null;
    }

    notifyListeners();
  }

  Future<void> _saveModels() async {
    final json = jsonEncode(_models.map((m) => m.toMap()).toList());
    await _cacheService.setEmbeddingModelsJson(json);
  }

  Future<EmbeddingModel?> importModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'litert', 'tflite', 'bin'],
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      if (file.path == null) return null;

      final model = EmbeddingModel(
        name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        path: file.path!,
        description: null,
      );

      _models.add(model);
      await _saveModels();
      notifyListeners();

      return model;
    } catch (e) {
      _error = 'Failed to import model: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> loadModel(EmbeddingModel model) async {
    if (_isLoading) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logService.log('EmbeddingModelProvider', 'Loading model: ${model.name} from ${model.path}');

      // Verify file exists
      final file = File(model.path);
      if (!await file.exists()) {
        _error = 'Model file not found: ${model.path}';
        _logService.log('EmbeddingModelProvider', 'ERROR: ${_error}');
        return false;
      }

      final fileSize = await file.length();
      _logService.log('EmbeddingModelProvider', 'Model file size: $fileSize bytes');

      final success = await _embeddingService.initialize(model.path);
      _logService.log('EmbeddingModelProvider', 'Embedding service initialized: $success');

      _isLoaded = success;
      _selectedModel = model;

      if (success) {
        await _cacheService.setSelectedEmbeddingModelId(model.id);
        await _cacheService.setEmbeddingModelLoaded(true);
        _logService.log('EmbeddingModelProvider', 'Model loaded successfully. Dimension: ${_embeddingService.embeddingDimension}');
      } else {
        _error = 'Failed to load embedding model';
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
    _embeddingService.dispose();
    _isLoaded = false;
    await _cacheService.setEmbeddingModelLoaded(false);
    notifyListeners();
  }

  Future<void> removeModel(String id) async {
    if (_selectedModel?.id == id) {
      await unloadModel();
      _selectedModel = null;
    }

    _models.removeWhere((m) => m.id == id);
    await _saveModels();
    notifyListeners();
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!_isLoaded) throw Exception('Embedding model not loaded');
    return await _embeddingService.embedBatch(texts);
  }

  Future<List<double>> embed(String text) async {
    if (!_isLoaded) throw Exception('Embedding model not loaded');
    return await _embeddingService.embed(text);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
