import 'package:flutter/foundation.dart';
import '../models/vector_db.dart';
import '../models/vector_chunk.dart';
import '../services/vector_db_service.dart';
import '../services/text_chunker.dart';
import '../services/log_service.dart';
import '../providers/embedding_model_provider.dart';

// Top-level function for isolate chunking
List<String> _chunkInIsolate(Map<String, dynamic> params) {
  final text = params['text'] as String;
  final chunkSize = params['chunkSize'] as int;
  final chunkOverlap = params['chunkOverlap'] as int;
  final chunker = TextChunker(chunkSize: chunkSize, overlap: chunkOverlap);
  return chunker.chunk(text);
}

class RagProvider extends ChangeNotifier {
  final EmbeddingModelProvider _embeddingProvider;
  final LogService _logService;

  List<VectorDb> _dbs = [];
  bool _isInitialized = false;
  String? _error;

  RagProvider({
    required EmbeddingModelProvider embeddingProvider,
    LogService? logService,
  })  : _embeddingProvider = embeddingProvider,
        _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  bool get isLoaded => _embeddingProvider.isLoaded;
  bool get isLoading => _embeddingProvider.isLoading;
  bool get hasDbs => _dbs.isNotEmpty;
  List<VectorDb> get dbs => _dbs;
  String? get error => _error;
  int get embeddingDimension => _embeddingProvider.embeddingDimension;
  EmbeddingModelProvider get embeddingProvider => _embeddingProvider;

  Future<void> loadDatabases() async {
    _logService.log('RagProvider', 'Loading databases...');
    try {
      _dbs = await VectorDbService.listDbs();
      _isInitialized = true;
      _logService.log('RagProvider', 'Loaded ${_dbs.length} databases');
      for (final db in _dbs) {
        _logService.log('RagProvider', '  DB: ${db.name} | chunks: ${db.chunkCount} | dim: ${db.embeddingDimension} | path: ${db.filePath}');
      }
      notifyListeners();
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to load databases', e, stackTrace);
    }
  }

  Future<VectorDb> createDatabase(String name, {int? chunkSize, int? overlap}) async {
    _logService.log('RagProvider', 'Creating database: $name');
    if (!_embeddingProvider.isLoaded) {
      _logService.log('RagProvider', 'ERROR: Embedding model not loaded');
      throw Exception('Embedding model not loaded');
    }

    final dim = _embeddingProvider.embeddingDimension;
    _logService.log('RagProvider', 'Embedding dimension: $dim');
    try {
      final db = await VectorDbService.createDb(name, dim);
      _logService.log('RagProvider', 'Database created: ${db.name} at ${db.filePath}');
      _dbs = await VectorDbService.listDbs();
      _logService.log('RagProvider', 'Total databases now: ${_dbs.length}');
      notifyListeners();
      return db;
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to create database: $name', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteDatabase(String name) async {
    _logService.log('RagProvider', 'Deleting database: $name');
    try {
      await VectorDbService.deleteDb(name);
      _dbs = await VectorDbService.listDbs();
      _logService.log('RagProvider', 'Database deleted. Total databases now: ${_dbs.length}');
      notifyListeners();
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to delete database: $name', e, stackTrace);
      rethrow;
    }
  }

  Future<void> processText({
    required String dbPath,
    required String text,
    String source = '',
    int chunkSize = 500,
    int chunkOverlap = 50,
    void Function(int current, int total, String chunkPreview)? onProgress,
  }) async {
    _logService.log('RagProvider', 'Processing text for DB: $dbPath');
    _logService.log('RagProvider', 'Text length: ${text.length} chars | source: ${source.isEmpty ? "(none)" : source}');
    _logService.log('RagProvider', 'Chunk size: $chunkSize | overlap: $chunkOverlap');

    if (!_embeddingProvider.isLoaded) {
      _logService.log('RagProvider', 'ERROR: Embedding model not loaded');
      throw Exception('Embedding model not loaded');
    }

    // Run chunking in an isolate to keep UI responsive
    _logService.log('RagProvider', 'Running chunking in isolate...');
    final chunks = await compute(_chunkInIsolate, {
      'text': text,
      'chunkSize': chunkSize,
      'chunkOverlap': chunkOverlap,
    });
    _logService.log('RagProvider', 'Text chunked into ${chunks.length} chunks (via isolate)');

    if (chunks.isEmpty) {
      _logService.log('RagProvider', 'No chunks generated, returning');
      return;
    }

    var totalEmbedded = 0;

    // Process ONE chunk at a time with memory monitoring
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final preview = chunk.length > 60 ? '${chunk.substring(0, 60)}...' : chunk;
      _logService.log('RagProvider', 'Processing chunk [$i/${chunks.length}]: $preview');

      try {
        // 1. Embed single chunk
        final vector = await _embeddingProvider.embed(chunk);
        _logService.log('RagProvider', '  Embedded: dim=${vector.length}');

        // 2. Store immediately to DB
        await VectorDbService.addChunks(dbPath, [chunk], [vector]);
        totalEmbedded++;
        _logService.log('RagProvider', '  Stored in DB. Total: $totalEmbedded/${chunks.length}');

        // 3. Clear intermediate data
        final _ = vector;

        // 4. Progress callback with chunk preview
        onProgress?.call(totalEmbedded, chunks.length, preview);

        // 5. Yield to UI + check memory every 5 chunks
        if (i % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
          // Force GC hint
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // 6. Refresh DB list so UI shows updated chunk count
        if (i % 3 == 0 || i == chunks.length - 1) {
          _dbs = await VectorDbService.listDbs();
          notifyListeners();
        }
      } catch (e, stackTrace) {
        _logService.logError('RagProvider', 'Failed to process chunk $i', e, stackTrace);
        _logService.log('RagProvider', 'Skipping chunk $i, continuing...');
      }
    }

    _logService.log('RagProvider', 'Text processing complete. Embedded: $totalEmbedded/${chunks.length}');
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  Future<List<VectorSearchResult>> search({
    required String query,
    List<String>? dbPaths,
    int topK = 5,
    double minScore = 0.3,
  }) async {
    _logService.log('RagProvider', 'Searching with query: "${query.length > 100 ? query.substring(0, 100) + "..." : query}"');
    _logService.log('RagProvider', 'Search params: topK=$topK, minScore=$minScore');

    if (!_embeddingProvider.isLoaded) {
      _logService.log('RagProvider', 'Search aborted: embedding model not loaded');
      return [];
    }

    try {
      _logService.log('RagProvider', 'Embedding query...');
      final queryVector = await _embeddingProvider.embed(query);
      _logService.log('RagProvider', 'Query embedded, vector dim: ${queryVector.length}');

      final paths = dbPaths ?? _dbs.map((d) => d.filePath).toList();
      _logService.log('RagProvider', 'Searching ${paths.length} database(s)');

      if (paths.isEmpty) {
        _logService.log('RagProvider', 'No databases to search');
        return [];
      }

      final results = await VectorDbService.search(
        dbPaths: paths,
        queryVector: queryVector,
        topK: topK,
        minScore: minScore,
      );

      _logService.log('RagProvider', 'Search returned ${results.length} results');
      for (var i = 0; i < results.length && i < 5; i++) {
        final r = results[i];
        final textPreview = r.text.length > 60 ? r.text.substring(0, 60) + '...' : r.text;
        _logService.log('RagProvider', '  Result[$i]: score=${r.score.toStringAsFixed(4)} db=${r.dbPath.split('/').last} text="$textPreview"');
      }

      return results;
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Search failed', e, stackTrace);
      _error = 'Search failed: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<VectorChunk>> loadChunks(String dbPath, {int? limit, int offset = 0}) async {
    _logService.log('RagProvider', 'Loading chunks from DB: $dbPath | offset=$offset limit=$limit');
    try {
      final chunks = await VectorDbService.loadChunks(dbPath, limit: limit, offset: offset);
      _logService.log('RagProvider', 'Loaded ${chunks.length} chunks');
      return chunks;
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to load chunks', e, stackTrace);
      return [];
    }
  }

  Future<void> editChunkText(String dbPath, int chunkId, String newText) async {
    _logService.log('RagProvider', 'Editing chunk $chunkId in DB: $dbPath');
    try {
      await VectorDbService.editText(dbPath, chunkId, newText);
      _dbs = await VectorDbService.listDbs();
      _logService.log('RagProvider', 'Chunk $chunkId edited successfully');
      notifyListeners();
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to edit chunk $chunkId', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteChunks(String dbPath, List<int> chunkIds) async {
    _logService.log('RagProvider', 'Deleting ${chunkIds.length} chunks from DB: $dbPath');
    try {
      await VectorDbService.deleteChunks(dbPath, chunkIds);
      _dbs = await VectorDbService.listDbs();
      _logService.log('RagProvider', 'Chunks deleted successfully');
      notifyListeners();
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Failed to delete chunks', e, stackTrace);
      rethrow;
    }
  }

  Future<void> addTextsToDb(String dbPath, List<String> texts) async {
    _logService.log('RagProvider', 'Adding ${texts.length} texts to DB: $dbPath');
    if (!_embeddingProvider.isLoaded) {
      _logService.log('RagProvider', 'ERROR: Embedding model not loaded');
      throw Exception('Embedding model not loaded');
    }

    var totalAdded = 0;
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      _logService.log('RagProvider', 'Processing text [$i/${texts.length}]');

      try {
        // 1. Embed single text
        final vector = await _embeddingProvider.embed(text);

        // 2. Store immediately
        await VectorDbService.addChunks(dbPath, [text], [vector]);
        totalAdded++;
        _logService.log('RagProvider', '  Stored. Total: $totalAdded/${texts.length}');

        // 3. Clear + refresh
        _dbs = await VectorDbService.listDbs();
        notifyListeners();
      } catch (e, stackTrace) {
        _logService.logError('RagProvider', 'Failed to process text $i', e, stackTrace);
        _logService.log('RagProvider', 'Skipping text $i, continuing...');
      }
    }

    _logService.log('RagProvider', 'All texts added: $totalAdded/${texts.length}');
    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  String buildRagPrompt(String userQuery, List<VectorSearchResult> results, String systemPrompt) {
    _logService.log('RagProvider', 'Building RAG prompt with ${results.length} context results');

    if (results.isEmpty) {
      _logService.log('RagProvider', 'No results, returning raw query');
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

    for (var i = 0; i < results.length; i++) {
      buffer.writeln('[Context ${i + 1}] (score: ${results[i].score.toStringAsFixed(3)})');
      buffer.writeln(results[i].text);
      buffer.writeln();
    }

    buffer.writeln('--- End Context ---');
    buffer.writeln();
    buffer.writeln('Question: $userQuery');
    buffer.write('Answer: ');

    final prompt = buffer.toString();
    _logService.log('RagProvider', 'RAG prompt built: ${prompt.length} chars (query: ${userQuery.length} chars, context: ${results.length} blocks)');
    return prompt;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
