import 'package:flutter/foundation.dart';
import '../models/vector_db.dart';
import '../models/vector_chunk.dart';
import '../services/embedding_service.dart';
import '../services/vector_db_service.dart';
import '../services/text_chunker.dart';
import '../providers/embedding_model_provider.dart';

class RagProvider extends ChangeNotifier {
  final EmbeddingModelProvider _embeddingProvider;

  List<VectorDb> _dbs = [];
  bool _isInitialized = false;
  String? _error;

  RagProvider({
    required EmbeddingModelProvider embeddingProvider,
  }) : _embeddingProvider = embeddingProvider;

  bool get isInitialized => _isInitialized;
  bool get isLoaded => _embeddingProvider.isLoaded;
  bool get isLoading => _embeddingProvider.isLoading;
  bool get hasDbs => _dbs.isNotEmpty;
  List<VectorDb> get dbs => _dbs;
  String? get error => _error;
  int get embeddingDimension => _embeddingProvider.embeddingDimension;
  EmbeddingModelProvider get embeddingProvider => _embeddingProvider;

  Future<void> loadDatabases() async {
    _dbs = await VectorDbService.listDbs();
    _isInitialized = true;
    notifyListeners();
  }

  Future<VectorDb> createDatabase(String name, {int? chunkSize, int? overlap}) async {
    if (!_embeddingProvider.isLoaded) {
      throw Exception('Embedding model not loaded');
    }

    final dim = _embeddingProvider.embeddingDimension;
    final db = await VectorDbService.createDb(name, dim);
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
    return db;
  }

  Future<void> deleteDatabase(String name) async {
    await VectorDbService.deleteDb(name);
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  Future<void> processText({
    required String dbPath,
    required String text,
    String source = '',
    int chunkSize = 500,
    int chunkOverlap = 50,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!_embeddingProvider.isLoaded) {
      throw Exception('Embedding model not loaded');
    }

    final chunker = TextChunker(chunkSize: chunkSize, overlap: chunkOverlap);
    final chunks = chunker.chunk(text);

    if (chunks.isEmpty) return;

    // Embed in batches of 32
    const batchSize = 32;
    for (var i = 0; i < chunks.length; i += batchSize) {
      final end = (i + batchSize > chunks.length) ? chunks.length : i + batchSize;
      final batch = chunks.sublist(i, end);

      final vectors = await _embeddingProvider.embedBatch(batch);
      await VectorDbService.addChunks(dbPath, batch, vectors);

      onProgress?.call(end, chunks.length);
    }

    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  Future<List<VectorSearchResult>> search({
    required String query,
    List<String>? dbPaths,
    int topK = 5,
    double minScore = 0.3,
  }) async {
    if (!_embeddingProvider.isLoaded) return [];

    try {
      final queryVector = await _embeddingProvider.embed(query);
      final paths = dbPaths ?? _dbs.map((d) => d.filePath).toList();

      if (paths.isEmpty) return [];

      return await VectorDbService.search(
        dbPaths: paths,
        queryVector: queryVector,
        topK: topK,
        minScore: minScore,
      );
    } catch (e) {
      _error = 'Search failed: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<VectorChunk>> loadChunks(String dbPath, {int? limit, int offset = 0}) async {
    return await VectorDbService.loadChunks(dbPath, limit: limit, offset: offset);
  }

  Future<void> editChunkText(String dbPath, int chunkId, String newText) async {
    await VectorDbService.editText(dbPath, chunkId, newText);
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  Future<void> deleteChunks(String dbPath, List<int> chunkIds) async {
    await VectorDbService.deleteChunks(dbPath, chunkIds);
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  Future<void> addTextsToDb(String dbPath, List<String> texts) async {
    if (!_embeddingProvider.isLoaded) throw Exception('Embedding model not loaded');

    const batchSize = 32;
    for (var i = 0; i < texts.length; i += batchSize) {
      final end = (i + batchSize > texts.length) ? texts.length : i + batchSize;
      final batch = texts.sublist(i, end);
      final vectors = await _embeddingProvider.embedBatch(batch);
      await VectorDbService.addChunks(dbPath, batch, vectors);
    }

    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  String buildRagPrompt(String userQuery, List<VectorSearchResult> results, String systemPrompt) {
    if (results.isEmpty) return userQuery;

    final buffer = StringBuffer();
    buffer.writeln(systemPrompt);
    buffer.writeln();
    buffer.writeln('Use the following context to answer the question. '
        'If the context does not contain relevant information, '
        'answer based on your general knowledge.');
    buffer.writeln();
    buffer.writeln('--- Context ---');

    for (var i = 0; i < results.length; i++) {
      buffer.writeln('[Context ${i + 1}] (score: ${results[i].score.toStringAsFixed(3)})');
      buffer.writeln(results[i].text);
      buffer.writeln();
    }

    buffer.writeln('--- End Context ---');
    buffer.writeln();
    buffer.writeln('Question: $userQuery');
    buffer.write('Answer: ');

    return buffer.toString();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
