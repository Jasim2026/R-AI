import 'package:flutter/foundation.dart';
import '../models/llm_model.dart';
import '../services/litert_service.dart';
import '../services/storage_service.dart';
import '../services/cache_service.dart';

class ModelProvider extends ChangeNotifier {
  final LiteRTService _litertService;
  final StorageService _storageService;
  final CacheService _cacheService;

  List<LLMModel> _models = [];
  bool _isLoading = false;
  String? _error;

  ModelProvider({
    required LiteRTService litertService,
    required StorageService storageService,
    required CacheService cacheService,
  })  : _litertService = litertService,
        _storageService = storageService,
        _cacheService = cacheService;

  List<LLMModel> get models => _models;
  bool get isLoading => _isLoading;
  String? get error => _error;
  LLMModel? get selectedModel => _litertService.currentModel;
  bool get isModelLoaded => _litertService.isModelLoaded;

  Future<void> loadModels() async {
    _isLoading = true;
    notifyListeners();

    try {
      _models = await _storageService.loadModels();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addModel(LLMModel model) async {
    _models.add(model);
    await _storageService.saveModels(_models);
    notifyListeners();
  }

  Future<void> removeModel(String modelId) async {
    final model = _models.firstWhere((m) => m.id == modelId);
    if (_litertService.currentModel?.id == modelId) {
      await _litertService.unloadModel();
    }
    await _storageService.deleteModelFile(model.path);
    _models.removeWhere((m) => m.id == modelId);
    await _storageService.saveModels(_models);
    notifyListeners();
  }

  Future<void> selectModel(LLMModel model) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _litertService.loadModel(model);
      _cacheService.lastModelId = model.id;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setDefaultModel(String modelId) async {
    _models = _models.map((m) {
      return m.copyWith(isDefault: m.id == modelId);
    }).toList();
    await _storageService.saveModels(_models);
    notifyListeners();
  }

  Future<void> unloadModel() async {
    await _litertService.unloadModel();
    _cacheService.lastModelId = null;
    notifyListeners();
  }
}