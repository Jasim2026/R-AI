import 'package:flutter/foundation.dart';
import '../services/cache_service.dart';

class SettingsProvider extends ChangeNotifier {
  final CacheService _cacheService;

  SettingsProvider({required CacheService cacheService})
      : _cacheService = cacheService;

  bool get cachePrompts => _cacheService.cachePrompts;
  String get systemPrompt => _cacheService.systemPrompt;
  double get temperature => _cacheService.temperature;
  double get topP => _cacheService.topP;
  int get maxTokens => _cacheService.maxTokens;
  bool get streamingEnabled => _cacheService.streamingEnabled;
  bool get ragEnabled => _cacheService.ragEnabled;
  int get ragTopK => _cacheService.ragTopK;

  Future<void> setCachePrompts(bool value) async {
    _cacheService.cachePrompts = value;
    notifyListeners();
  }

  Future<void> setSystemPrompt(String value) async {
    _cacheService.systemPrompt = value;
    notifyListeners();
  }

  Future<void> setTemperature(double value) async {
    _cacheService.temperature = value;
    notifyListeners();
  }

  Future<void> setTopP(double value) async {
    _cacheService.topP = value;
    notifyListeners();
  }

  Future<void> setMaxTokens(int value) async {
    _cacheService.maxTokens = value;
    notifyListeners();
  }

  Future<void> setStreamingEnabled(bool value) async {
    _cacheService.streamingEnabled = value;
    notifyListeners();
  }

  Future<void> setRagEnabled(bool value) async {
    _cacheService.ragEnabled = value;
    notifyListeners();
  }

  Future<void> setRagTopK(int value) async {
    _cacheService.ragTopK = value;
    notifyListeners();
  }

  Future<void> clearPromptCache() async {
    await _cacheService.clearPromptCache();
  }

  Future<void> resetToDefaults() async {
    _cacheService.cachePrompts = false;
    _cacheService.systemPrompt =
        'You are a helpful, harmless, and honest AI assistant.';
    _cacheService.temperature = 0.7;
    _cacheService.topP = 0.9;
    _cacheService.maxTokens = 4096;
    _cacheService.streamingEnabled = true;
    notifyListeners();
  }
}
