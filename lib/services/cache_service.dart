import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static CacheService? _instance;
  late final SharedPreferences _prefs;

  CacheService._();

  static Future<CacheService> getInstance() async {
    if (_instance == null) {
      _instance = CacheService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get cachePrompts => _prefs.getBool('cache_prompts') ?? false;
  set cachePrompts(bool value) => _prefs.setBool('cache_prompts', value);

  String get systemPrompt =>
      _prefs.getString('system_prompt') ??
      'You are a helpful, harmless, and honest AI assistant.';
  set systemPrompt(String value) => _prefs.setString('system_prompt', value);

  double get temperature => _prefs.getDouble('temperature') ?? 0.7;
  set temperature(double value) => _prefs.setDouble('temperature', value);

  double get topP => _prefs.getDouble('top_p') ?? 0.9;
  set topP(double value) => _prefs.setDouble('top_p', value);

  int get maxTokens => _prefs.getInt('max_tokens') ?? 4096;
  set maxTokens(int value) => _prefs.setInt('max_tokens', value);

  bool get streamingEnabled => _prefs.getBool('streaming_enabled') ?? true;
  set streamingEnabled(bool value) =>
      _prefs.setBool('streaming_enabled', value);

  bool get ragEnabled => _prefs.getBool('rag_enabled') ?? false;
  set ragEnabled(bool value) => _prefs.setBool('rag_enabled', value);

  int get ragTopK => _prefs.getInt('rag_top_k') ?? 5;
  set ragTopK(int value) => _prefs.setInt('rag_top_k', value);

  String? get lastModelId => _prefs.getString('last_model_id');
  set lastModelId(String? value) {
    if (value != null) {
      _prefs.setString('last_model_id', value);
    } else {
      _prefs.remove('last_model_id');
    }
  }

  String? get embeddingModelsJson => _prefs.getString('embedding_models');
  Future<void> setEmbeddingModelsJson(String value) => _prefs.setString('embedding_models', value);

  String? get selectedEmbeddingModelId => _prefs.getString('selected_embedding_model_id');
  Future<void> setSelectedEmbeddingModelId(String? value) {
    if (value != null) {
      return _prefs.setString('selected_embedding_model_id', value);
    }
    return _prefs.remove('selected_embedding_model_id');
  }

  bool get embeddingModelLoaded => _prefs.getBool('embedding_model_loaded') ?? false;
  Future<void> setEmbeddingModelLoaded(bool value) => _prefs.setBool('embedding_model_loaded', value);

  int get chunkSize => _prefs.getInt('chunk_size') ?? 500;
  set chunkSize(int value) => _prefs.setInt('chunk_size', value);

  int get chunkOverlap => _prefs.getInt('chunk_overlap') ?? 50;
  set chunkOverlap(int value) => _prefs.setInt('chunk_overlap', value);

  String get ragMode => _prefs.getString('rag_mode') ?? 'pre_generation';
  set ragMode(String value) => _prefs.setString('rag_mode', value);

  bool get toolCallingEnabled => _prefs.getBool('tool_calling_enabled') ?? false;
  set toolCallingEnabled(bool value) => _prefs.setBool('tool_calling_enabled', value);

  String? get toolsJson => _prefs.getString('tools_json');
  Future<void> setToolsJson(String value) => _prefs.setString('tools_json', value);

  String get uncertaintyKeywords =>
      _prefs.getString('uncertainty_keywords') ??
      'I am not sure,I don\'t know,I cannot confirm,uncertain,not certain,unable to determine';
  set uncertaintyKeywords(String value) =>
      _prefs.setString('uncertainty_keywords', value);

  String _cacheKey(String modelId, String prompt, double temp, double topP, int maxTok) {
    return 'prompt_cache_${modelId}_${temp}_${topP}_${maxTok}_${prompt.hashCode}';
  }

  Future<void> savePromptCache(String modelId, String prompt, String response) async {
    final key = _cacheKey(modelId, prompt, temperature, topP, maxTokens);
    final data = {
      'prompt': prompt,
      'response': response,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _prefs.setString(key, jsonEncode(data));
  }

  String? getCachedResponse(String modelId, String prompt) {
    final key = _cacheKey(modelId, prompt, temperature, topP, maxTokens);
    final data = _prefs.getString(key);
    if (data == null) return null;

    final map = jsonDecode(data) as Map<String, dynamic>;
    final timestamp = DateTime.parse(map['timestamp']);

    if (DateTime.now().difference(timestamp).inHours > 24) {
      _prefs.remove(key);
      return null;
    }

    return map['response'] as String;
  }

  Future<void> clearPromptCache() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('prompt_cache_'));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
