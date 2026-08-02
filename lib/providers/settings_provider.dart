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

  void setCachePrompts(bool value) {
    _cacheService.cachePrompts = value;
    notifyListeners();
  }

  void setSystemPrompt(String value) {
    _cacheService.systemPrompt = value;
    notifyListeners();
  }

  void setTemperature(double value) {
    _cacheService.temperature = value;
    notifyListeners();
  }

  void setTopP(double value) {
    _cacheService.topP = value;
    notifyListeners();
  }

  void setMaxTokens(int value) {
    _cacheService.maxTokens = value;
    notifyListeners();
  }

  void setStreamingEnabled(bool value) {
    _cacheService.streamingEnabled = value;
    notifyListeners();
  }

  void setRagEnabled(bool value) {
    _cacheService.ragEnabled = value;
    notifyListeners();
  }

  void setRagTopK(int value) {
    _cacheService.ragTopK = value;
    notifyListeners();
  }

  Future<void> clearPromptCache() async {
    await _cacheService.clearPromptCache();
  }

  void resetToDefaults() {
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
