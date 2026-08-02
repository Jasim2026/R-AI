import 'package:flutter/foundation.dart';
import '../models/llm_model.dart';
import '../services/litert_service.dart';
import '../services/storage_service.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';

class ModelProvider extends ChangeNotifier {
  final LiteRTService _litertService;
  final StorageService _storageService;
  final CacheService _cacheService;
  final LogService _logService;

  List<LLMModel> _models = [];
  bool _isLoading = false;
  String? _error;

  ModelProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
    LogService? logService,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService,
        _logService = logService ?? LogService();

  List<LLMModel> get models => _models;
  bool get isLoading => _isLoading;
  String? get error => _error;
  LLMModel? get selectedModel => _litertService.currentModel;
  bool get isModelLoaded => _litertService.isModelLoaded;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadModels() async {
    _logService.log('ModelProvider', 'Loading saved LLM models...');
    _isLoading = true;
    notifyListeners();

    try {
      _models = await _storageService.loadModels();
      _error = null;
      _logService.log('ModelProvider', 'Loaded ${_models.length} models');
      for (final m in _models) {
        _logService.log('ModelProvider', '  Model: ${m.name} | id=${m.id} | backend=${m.backendName} | path=${m.path}');
      }
    } catch (e) {
      _logService.logError('ModelProvider', 'Failed to load models', e, null);
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addModel(LLMModel model) async {
    _logService.log('ModelProvider', 'Adding model: ${model.name} (${model.id})');
    _logService.log('ModelProvider', 'Path: ${model.path}');
    _logService.log('ModelProvider', 'Backend: ${model.backendName}');
    _models.add(model);
    await _storageService.saveModels(_models);
    _logService.log('ModelProvider', 'Model added. Total models: ${_models.length}');
    notifyListeners();
  }

  Future<void> removeModel(String modelId) async {
    _logService.log('ModelProvider', 'Removing model: $modelId');
    final model = _models.firstWhere((m) => m.id == modelId);
    _logService.log('ModelProvider', 'Model to remove: ${model.name} at ${model.path}');

    if (_litertService.currentModel?.id == modelId) {
      _logService.log('ModelProvider', 'Model is currently loaded, unloading first...');
      await _litertService.unloadModel();
    }

    _logService.log('ModelProvider', 'Deleting model file...');
    await _storageService.deleteModelFile(model.path);
    _models.removeWhere((m) => m.id == modelId);
    await _storageService.saveModels(_models);
    _logService.log('ModelProvider', 'Model removed. Remaining models: ${_models.length}');
    notifyListeners();
  }

  Future<bool> selectModel(LLMModel model) async {
    _logService.log('ModelProvider', '=== Selecting LLM model: ${model.name} ===');
    _logService.log('ModelProvider', 'Model ID: ${model.id}');
    _logService.log('ModelProvider', 'Path: ${model.path}');
    _logService.log('ModelProvider', 'Backend: ${model.backendName}');
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _logService.log('ModelProvider', 'Calling LiteRTService.loadModel()...');
      await _litertService.loadModel(model);
      _cacheService.lastModelId = model.id;
      _logService.log('ModelProvider', '=== Model selected successfully ===');
      notifyListeners();
      return true;
    } catch (e) {
      _logService.logError('ModelProvider', 'Failed to select model', e, null);
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setDefaultModel(String modelId) async {
    _logService.log('ModelProvider', 'Setting default model: $modelId');
    _models = _models.map((m) {
      final isDefault = m.id == modelId;
      if (isDefault) {
        _logService.log('ModelProvider', 'Default model set: ${m.name}');
      }
      return m.copyWith(isDefault: isDefault);
    }).toList();
    await _storageService.saveModels(_models);
    notifyListeners();
  }

  Future<void> unloadModel() async {
    _logService.log('ModelProvider', 'Unloading LLM model...');
    await _litertService.unloadModel();
    _cacheService.lastModelId = null;
    _logService.log('ModelProvider', 'Model unloaded');
    notifyListeners();
  }
}
