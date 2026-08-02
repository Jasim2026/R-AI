import 'embedding_service.dart';
import 'vector_service.dart';

class RagService {
  final EmbeddingService _embeddingService;
  final VectorService _vectorService;

  bool _isReady = false;
  bool get isReady => _isReady;

  RagService({
    required EmbeddingService embeddingService,
    required VectorService vectorService,
  })  : _embeddingService = embeddingService,
        _vectorService = vectorService;

  Future<void> initialize(String embeddingModelPath) async {
    try {
      await _embeddingService.initialize(embeddingModelPath);
      _isReady = _embeddingService.isInitialized && _vectorService.isInitialized;
    } catch (e) {
      _isReady = false;
    }
  }

  Future<RagResult> retrieve(String query, {int topK = 5}) async {
    if (!_isReady) {
      return RagResult(context: '', chunks: [], scores: []);
    }

    try {
      // Step 1: Embed the query
      final queryEmbedding = await _embeddingService.embed(query);

      // Step 2: Search vector database
      final searchResults = await _vectorService.search(
        queryEmbedding: queryEmbedding,
        topK: topK,
        minScore: 0.3,
      );

      if (searchResults.isEmpty) {
        return RagResult(context: '', chunks: [], scores: []);
      }

      // Step 3: Build context from retrieved chunks
      final contextBuffer = StringBuffer();
      final chunks = <String>[];
      final scores = <double>[];

      for (int i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
        chunks.add(result.text);
        scores.add(result.score);
        contextBuffer.writeln('[Context ${i + 1}] (score: ${result.score.toStringAsFixed(3)})');
        contextBuffer.writeln(result.text);
        contextBuffer.writeln();
      }

      return RagResult(
        context: contextBuffer.toString(),
        chunks: chunks,
        scores: scores,
      );
    } catch (e) {
      return RagResult(context: '', chunks: [], scores: []);
    }
  }

  String buildRagPrompt(String userQuery, RagResult ragResult, String systemPrompt) {
    if (ragResult.context.isEmpty) {
      return userQuery;
    }

    final buffer = StringBuffer();
    buffer.writeln(systemPrompt);
    buffer.writeln();
    buffer.writeln('Use the following context to answer the question. '
        'If the context does not contain relevant information, '
        'answer based on your general knowledge.');
    buffer.writeln();
    buffer.writeln('--- Context ---');
    buffer.writeln(ragResult.context);
    buffer.writeln('--- End Context ---');
    buffer.writeln();
    buffer.writeln('Question: $userQuery');
    buffer.write('Answer: ');

    return buffer.toString();
  }

  void dispose() {
    _embeddingService.dispose();
  }
}

class RagResult {
  final String context;
  final List<String> chunks;
  final List<double> scores;

  RagResult({
    required this.context,
    required this.chunks,
    required this.scores,
  });

  bool get hasResults => chunks.isNotEmpty;
}
