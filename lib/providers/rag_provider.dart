import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/vector_db.dart';
import '../models/vector_chunk.dart';
import '../models/message.dart';
import '../services/vector_db_service.dart';
import '../services/keyword_db_service.dart';
import '../services/keyword_search_engine.dart';
import '../services/text_chunker.dart';
import '../services/log_service.dart';
import '../services/ram_monitor_service.dart';
import '../services/cache_service.dart';
import '../providers/embedding_model_provider.dart';

class RagProvider extends ChangeNotifier {
  final EmbeddingModelProvider _embeddingProvider;
  final LogService _logService;
  final RamMonitorService _ramMonitor;

  List<VectorDb> _dbs = [];
  bool _isInitialized = false;
  String? _error;

  RagProvider({
    required EmbeddingModelProvider embeddingProvider,
    RamMonitorService? ramMonitor,
    LogService? logService,
  })  : _embeddingProvider = embeddingProvider,
        _ramMonitor = ramMonitor ?? RamMonitorService(),
        _logService = logService ?? LogService();

  bool get isInitialized => _isInitialized;
  bool get isLoaded => _embeddingProvider.isLoaded;
  bool get isLoading => _embeddingProvider.isLoading;
  bool get hasDbs => _dbs.isNotEmpty;
  List<VectorDb> get dbs => _dbs;
  String? get error => _error;
  int get embeddingDimension => _embeddingProvider.embeddingDimension;
  EmbeddingModelProvider get embeddingProvider => _embeddingProvider;

  /// Check if enough RAM is available before embedding.
  /// Returns true if safe to proceed, false if should pause/abort.
  Future<bool> _checkRamBeforeEmbed(int chunkIndex, int totalChunks) async {
    final info = _ramMonitor.lastInfo;
    if (info == null || info.totalGb == 0) return true; // can't check, proceed

    final availableMb = (info.totalGb - info.usedGb) * 1024;
    final usedPct = info.percentage;

    _logService.log('RagProvider', 'RAM check before chunk $chunkIndex/$totalChunks: '
        '${availableMb.toStringAsFixed(0)}MB available (${usedPct.toStringAsFixed(1)}% used)');

    if (usedPct > 90) {
      _logService.log('RagProvider', 'RAM CRITICAL (${usedPct.toStringAsFixed(1)}%) — forcing GC + pause');
      // Force garbage collection hint
      await Future.delayed(const Duration(milliseconds: 500));
      // Re-check after pause
      final recheck = _ramMonitor.lastInfo;
      if (recheck != null && recheck.percentage > 92) {
        _logService.log('RagProvider', 'RAM still critical after pause — aborting chunk $chunkIndex');
        return false;
      }
    } else if (usedPct > 80) {
      _logService.log('RagProvider', 'RAM high (${usedPct.toStringAsFixed(1)}%) — adding delay');
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return true;
  }

  Future<void> loadDatabases() async {
    _logService.log('RagProvider', 'Loading databases...');
    try {
      _dbs = await VectorDbService.listDbs();

      // Also load keyword DB names for display
      final keywordDbs = await KeywordDbService.listDbs();
      for (final name in keywordDbs) {
        // Add keyword DBs that aren't already in the vector list
        if (!_dbs.any((d) => d.name == name)) {
          final count = await KeywordDbService.countChunks(name);
          _dbs.add(VectorDb(
            name: name,
            filePath: 'keyword://$name',
            chunkCount: count,
            embeddingDimension: 0, // 0 = keyword mode
          ));
        }
      }

      _isInitialized = true;
      _logService.log('RagProvider', 'Loaded ${_dbs.length} databases (${_dbs.where((d) => d.embeddingDimension > 0).length} vector, ${keywordDbs.length} keyword)');
      for (final db in _dbs) {
        _logService.log('RagProvider', '  DB: ${db.name} | chunks: ${db.chunkCount} | mode: ${db.embeddingDimension > 0 ? "vector" : "keyword"}');
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
      // Delete from both stores
      final vectorDb = await VectorDbService.listDbs();
      if (vectorDb.any((d) => d.name == name)) {
        await VectorDbService.deleteDb(name);
      }
      final keywordDbs = await KeywordDbService.listDbs();
      if (keywordDbs.contains(name)) {
        await KeywordDbService.deleteDb(name);
      }
      _dbs = await VectorDbService.listDbs();

      // Re-add keyword DBs to list
      final kDbs = await KeywordDbService.listDbs();
      for (final kName in kDbs) {
        if (!_dbs.any((d) => d.name == kName)) {
          final count = await KeywordDbService.countChunks(kName);
          _dbs.add(VectorDb(
            name: kName,
            filePath: 'keyword://$kName',
            chunkCount: count,
            embeddingDimension: 0,
          ));
        }
      }

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
    String? dbName,
    String source = '',
    int chunkSize = 500,
    int chunkOverlap = 50,
    String? separator,
    String? searchMode,
    void Function(int current, int total, String chunkPreview)? onProgress,
  }) async {
    final mode = searchMode ?? 'vector';
    _logService.log('RagProvider', 'Processing text for DB: ${dbName ?? dbPath} (mode=$mode)');
    _logService.log('RagProvider', 'Text length: ${text.length} chars | source: ${source.isEmpty ? "(none)" : source}');
    _logService.log('RagProvider', 'Chunk size: $chunkSize | overlap: $chunkOverlap | separator: ${separator ?? "(none)"}');

    // Chunk synchronously on main thread
    _logService.log('RagProvider', 'Chunking text synchronously...');
    final chunker = TextChunker(
      chunkSize: chunkSize,
      overlap: chunkOverlap,
      delimiter: separator,
    );
    final chunks = chunker.chunk(text);
    _logService.log('RagProvider', 'Text chunked into ${chunks.length} chunks');

    if (chunks.isEmpty) {
      _logService.log('RagProvider', 'No chunks generated, returning');
      return;
    }

    // Keyword mode: store in SQLite, no embedding model needed
    if (mode == 'keyword') {
      final kwName = dbName ?? dbPath.split('/').last.replaceAll('.db', '');
      _logService.log('RagProvider', 'Storing ${chunks.length} chunks in keyword DB: $kwName');
      await KeywordDbService.addChunks(kwName, chunks, source: source);
      onProgress?.call(chunks.length, chunks.length, 'Done');
      _dbs = await VectorDbService.listDbs();
      // Re-add keyword DBs
      final kwDbs = await KeywordDbService.listDbs();
      for (final kName in kwDbs) {
        if (!_dbs.any((d) => d.name == kName)) {
          final count = await KeywordDbService.countChunks(kName);
          _dbs.add(VectorDb(
            name: kName,
            filePath: 'keyword://$kName',
            chunkCount: count,
            embeddingDimension: 0,
          ));
        }
      }
      notifyListeners();
      return;
    }

    // Vector mode: requires embedding model
    if (!_embeddingProvider.isLoaded) {
      _logService.log('RagProvider', 'ERROR: Embedding model not loaded');
      throw Exception('Embedding model not loaded');
    }

    var totalEmbedded = 0;
    var abortedDueToRam = false;

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final preview = chunk.length > 60 ? '${chunk.substring(0, 60)}...' : chunk;
      _logService.log('RagProvider', 'Processing chunk [$i/${chunks.length}]: $preview');

      final ramOk = await _checkRamBeforeEmbed(i, chunks.length);
      if (!ramOk) {
        _logService.log('RagProvider', 'Aborting due to low RAM at chunk $i');
        abortedDueToRam = true;
        break;
      }

      try {
        final vector = await _embeddingProvider.embed(chunk);
        _logService.log('RagProvider', '  Embedded: dim=${vector.length}');

        await VectorDbService.addChunks(dbPath, [chunk], [vector]);
        totalEmbedded++;
        _logService.log('RagProvider', '  Stored in DB. Total: $totalEmbedded/${chunks.length}');

        await Future.delayed(const Duration(milliseconds: 20));

        if (i % 3 == 0 || i == chunks.length - 1) {
          _dbs = await VectorDbService.listDbs();
          notifyListeners();
        }

        onProgress?.call(totalEmbedded, chunks.length, preview);
      } catch (e, stackTrace) {
        _logService.logError('RagProvider', 'Failed to process chunk $i', e, stackTrace);
        _logService.log('RagProvider', 'Skipping chunk $i, continuing...');

        final errStr = e.toString().toLowerCase();
        if (errStr.contains('out of memory') || errStr.contains('oom') || errStr.contains('alloc')) {
          _logService.log('RagProvider', 'OOM detected in embed — aborting remaining chunks');
          abortedDueToRam = true;
          break;
        }
      }
    }

    if (abortedDueToRam) {
      _logService.log('RagProvider', 'Processing stopped due to memory constraints. Embedded: $totalEmbedded/${chunks.length}');
    } else {
      _logService.log('RagProvider', 'Text processing complete. Embedded: $totalEmbedded/${chunks.length}');
    }

    _dbs = await VectorDbService.listDbs();
    notifyListeners();
  }

  /// Keyword search — uses BM25 scoring, no embedding model needed.
  Future<List<KeywordSearchResult>> searchKeyword({
    required String query,
    List<String>? dbNames,
    int topK = 5,
    double minScore = 0.01,
  }) async {
    _logService.log('RagProvider', 'Keyword search: "${query.length > 80 ? query.substring(0, 80) + "..." : query}" minScore=$minScore');

    try {
      final results = await KeywordDbService.search(
        query: query,
        dbNames: dbNames,
        topK: topK,
        minScore: minScore,
      );

      _logService.log('RagProvider', 'Keyword search returned ${results.length} results');
      for (var i = 0; i < results.length && i < 5; i++) {
        final r = results[i];
        _logService.log('RagProvider', '  Result[$i]: score=${r.score.toStringAsFixed(4)} db=${r.dbName} chunkId=${r.chunkId}');
      }

      return results;
    } catch (e, stackTrace) {
      _logService.logError('RagProvider', 'Keyword search failed', e, stackTrace);
      _error = 'Keyword search failed: $e';
      notifyListeners();
      return [];
    }
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

      // RAM guard
      final ramOk = await _checkRamBeforeEmbed(i, texts.length);
      if (!ramOk) {
        _logService.log('RagProvider', 'Aborting addTexts due to low RAM');
        break;
      }

      try {
        // 1. Embed single text
        final vector = await _embeddingProvider.embed(text);

        // 2. Store immediately
        await VectorDbService.addChunks(dbPath, [text], [vector]);
        totalAdded++;
        _logService.log('RagProvider', '  Stored. Total: $totalAdded/${texts.length}');

        // 3. Yield + refresh
        await Future.delayed(const Duration(milliseconds: 20));
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

  String buildRagPromptFromContexts(String userQuery, List<RagContext> contexts, String systemPrompt) {
    _logService.log('RagProvider', 'Building RAG prompt from ${contexts.length} contexts');

    if (contexts.isEmpty) {
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

    for (var i = 0; i < contexts.length; i++) {
      buffer.writeln('[Context ${i + 1}] (score: ${contexts[i].score.toStringAsFixed(3)})');
      buffer.writeln(contexts[i].text);
      buffer.writeln();
    }

    buffer.writeln('--- End Context ---');
    buffer.writeln();
    buffer.writeln('Question: $userQuery');
    buffer.write('Answer: ');

    final prompt = buffer.toString();
    _logService.log('RagProvider', 'RAG prompt built: ${prompt.length} chars (query: ${userQuery.length} chars, context: ${contexts.length} blocks)');
    return prompt;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
