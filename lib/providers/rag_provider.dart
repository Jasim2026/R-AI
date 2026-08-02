import 'package:flutter/foundation.dart';
import '../services/rag_service.dart';
import '../services/embedding_service.dart';
import '../services/vector_service.dart';

class RagProvider extends ChangeNotifier {
  RagService? _ragService;

  bool _isEnabled = false;
  bool _isInitialized = false;
  bool _isRetrieving = false;
  String _lastQuery = '';
  int _lastResultsCount = 0;

  RagProvider({
    required RagService ragService,
  }) : _ragService = ragService;

  RagProvider.lazy();

  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;
  bool get isRetrieving => _isRetrieving;
  bool get isReady => _ragService?.isReady ?? false;
  String get lastQuery => _lastQuery;
  int get lastResultsCount => _lastResultsCount;

  Future<void> _ensureInitialized() async {
    if (_ragService != null) return;
    final embeddingService = EmbeddingService();
    final vectorService = await VectorService.getInstance();
    _ragService = RagService(
      embeddingService: embeddingService,
      vectorService: vectorService,
    );
  }

  void toggleRag() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  void setEnabled(bool value) {
    _isEnabled = value;
    notifyListeners();
  }

  Future<void> initialize(String embeddingModelPath) async {
    try {
      await _ensureInitialized();
      await _ragService!.initialize(embeddingModelPath);
      _isInitialized = _ragService!.isReady;
      notifyListeners();
    } catch (e) {
      _isInitialized = false;
      notifyListeners();
    }
  }

  Future<RagResult> retrieve(String query) async {
    if (!_isEnabled || !_isInitialized || _ragService == null) {
      return RagResult(context: '', chunks: [], scores: []);
    }

    _isRetrieving = true;
    _lastQuery = query;

    try {
      final result = await _ragService!.retrieve(query);
      _lastResultsCount = result.chunks.length;
      return result;
    } catch (e) {
      return RagResult(context: '', chunks: [], scores: []);
    } finally {
      _isRetrieving = false;
    }
  }

  String buildRagPrompt(String userQuery, RagResult ragResult, String systemPrompt) {
    return _ragService?.buildRagPrompt(userQuery, ragResult, systemPrompt) ?? '';
  }

  @override
  void dispose() {
    _ragService?.dispose();
    super.dispose();
  }
}
