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

  String get ragOnSystemPrompt =>
      _prefs.getString('rag_on_system_prompt') ??
      'You are a helpful AI assistant. Answer the question STRICTLY using ONLY the provided context. '
      'If the context does not contain enough information to answer, say "I don\'t have enough information in the provided context to answer this question." '
      'Do not use any outside knowledge. Do not make assumptions. '
      'Base your answer entirely on the context provided below.';
  set ragOnSystemPrompt(String value) => _prefs.setString('rag_on_system_prompt', value);

  String get ragOffSystemPrompt =>
      _prefs.getString('rag_off_system_prompt') ??
      'You are a helpful, harmless, and honest AI assistant. Answer based on your general knowledge.';
  set ragOffSystemPrompt(String value) => _prefs.setString('rag_off_system_prompt', value);

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

  bool get chunkAutoSize => _prefs.getBool('chunk_auto_size') ?? true;
  set chunkAutoSize(bool value) => _prefs.setBool('chunk_auto_size', value);

  String get chunkSeparator => _prefs.getString('chunk_separator') ?? '';
  set chunkSeparator(String value) => _prefs.setString('chunk_separator', value);

  // Search mode: 'keyword' (default, no model needed) or 'vector' (requires embedding model)
  String get searchMode => _prefs.getString('search_mode') ?? 'keyword';
  set searchMode(String value) => _prefs.setString('search_mode', value);

  bool get isKeywordSearch => searchMode == 'keyword';
  bool get isVectorSearch => searchMode == 'vector';

  String get ragMode => _prefs.getString('rag_mode') ?? 'pre_generation';
  set ragMode(String value) => _prefs.setString('rag_mode', value);

  // Keyword RAG minimum similarity threshold (percentage 0-100)
  // Represents % of max BM25 score; higher = stricter filtering
  double get ragMinScorePercent => _prefs.getDouble('rag_min_score_pct') ?? _defaultMinScorePercent;
  set ragMinScorePercent(double value) => _prefs.setDouble('rag_min_score_pct', value);

  bool get ragMinScoreOverridden => _prefs.containsKey('rag_min_score_pct');

  /// Compute dynamic default threshold percentage based on query + DB size.
  ///
  /// Algorithm:
  ///   - Few keywords (1-2): lower % (15%) — cast wider net
  ///   - Moderate keywords (3-4): 25%
  ///   - Many keywords (5+): 35% — strong signal, filter harder
  ///   - Large DB (>500 chunks): +5% boost — more noise to filter
  static double computeDefaultThresholdPercent(String query, {int chunkCount = 0}) {
    const stopwords = {
      'a','an','the','and','or','but','if','in','on','at','to','for','of','with',
      'by','from','as','is','was','are','were','be','been','being','have','has',
      'had','do','does','did','will','would','could','should','may','might',
      'shall','can','not','no','nor','so','too','very','just','than','that',
      'this','these','those','it','its','he','she','they','we','you','i','me',
      'my','your','his','her','our','their','what','which','who','whom','where',
      'when','why','how','all','any','both','each','few','more','most','other',
      'some','such','own','same','then','here','there','also','about','into',
      'over','after','before','between','under','again','once','only','even',
      'still','already','always','never','often','sometimes','usually','now',
      'well','yes','maybe','thing','things','way','ways','much','many',
    };

    final words = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !stopwords.contains(w))
        .toList();

    final kw = words.length;

    // Base percentage from keyword count
    double pct;
    if (kw <= 2) {
      pct = 15.0;
    } else if (kw <= 4) {
      pct = 25.0;
    } else {
      pct = 35.0;
    }

    // Large DB boost — more chunks means more noise, raise threshold
    if (chunkCount > 500) pct += 5.0;
    if (chunkCount > 1000) pct += 5.0;

    return pct.clamp(5.0, 80.0);
  }

  double get _defaultMinScorePercent {
    return _prefs.getDouble('rag_default_min_score_pct') ?? 20.0;
  }

  /// Cache the computed default for the current query so seekbar starts at the right spot
  void cacheDefaultMinScore(String query, {int chunkCount = 0}) {
    _prefs.setDouble('rag_default_min_score_pct', computeDefaultThresholdPercent(query, chunkCount: chunkCount));
  }

  bool get toolCallingEnabled => _prefs.getBool('tool_calling_enabled') ?? false;
  set toolCallingEnabled(bool value) => _prefs.setBool('tool_calling_enabled', value);

  // Last RAG inference chunk tracking
  String? get lastRagChunkIds => _prefs.getString('last_rag_chunk_ids');
  set lastRagChunkIds(String? value) {
    if (value != null) {
      _prefs.setString('last_rag_chunk_ids', value);
    } else {
      _prefs.remove('last_rag_chunk_ids');
    }
  }

  String? get lastRagDbNames => _prefs.getString('last_rag_db_names');
  set lastRagDbNames(String? value) {
    if (value != null) {
      _prefs.setString('last_rag_db_names', value);
    } else {
      _prefs.remove('last_rag_db_names');
    }
  }

  // Per-session selected databases (comma-separated names, empty = all)
  String get selectedRagDbs => _prefs.getString('selected_rag_dbs') ?? '';
  set selectedRagDbs(String value) => _prefs.setString('selected_rag_dbs', value);

  List<String> get selectedRagDbList {
    final raw = selectedRagDbs;
    if (raw.isEmpty) return [];
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

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
