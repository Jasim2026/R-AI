import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../services/log_service.dart';
import '../services/keyword_search_engine.dart';

/// SQLite-backed store for text-only chunks used by keyword search.
///
/// When the user's search mode is "keyword" (default), documents are chunked
/// and stored here WITHOUT requiring an embedding model. This allows RAG
/// to work without any model loaded.
class KeywordDbService {
  static const _dbName = 'keyword_rag.db';
  static Database? _db;
  static final LogService _logService = LogService();

  /// Get or open the shared keyword database.
  static Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDir.path}/$_dbName';
    _logService.log('KeywordDbService', 'Opening database: $dbPath');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            db_name TEXT NOT NULL,
            chunk_idx INTEGER NOT NULL,
            text TEXT NOT NULL,
            source TEXT DEFAULT ''
          )
        ''');
        await db.execute('CREATE INDEX idx_chunks_db ON chunks(db_name)');
        await db.execute('CREATE INDEX idx_chunks_db_idx ON chunks(db_name, chunk_idx)');
        _logService.log('KeywordDbService', 'Created chunks table + indexes');
      },
    );

    return _db!;
  }

  /// Get all distinct DB names in the keyword store.
  static Future<List<String>> listDbs() async {
    final db = await _getDb();
    final result = await db.rawQuery('SELECT DISTINCT db_name FROM chunks ORDER BY db_name');
    return result.map((r) => r['db_name'] as String).toList();
  }

  /// Count chunks in a DB.
  static Future<int> countChunks(String dbName) async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM chunks WHERE db_name = ?',
      [dbName],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Add chunks to a DB. Replaces all existing chunks for this DB name
  /// (idempotent — useful for re-processing).
  static Future<void> addChunks(String dbName, List<String> texts, {String source = ''}) async {
    _logService.log('KeywordDbService', 'Adding ${texts.length} chunks to: $dbName');
    final db = await _getDb();

    // Remove existing chunks for this DB (re-process)
    await db.delete('chunks', where: 'db_name = ?', whereArgs: [dbName]);

    // Insert new chunks
    final batch = db.batch();
    for (var i = 0; i < texts.length; i++) {
      batch.insert('chunks', {
        'db_name': dbName,
        'chunk_idx': i,
        'text': texts[i],
        'source': source,
      });
    }
    await batch.commit(noResult: true);
    _logService.log('KeywordDbService', 'Inserted ${texts.length} chunks for $dbName');
  }

  /// Append chunks to a DB (for incremental additions).
  static Future<void> appendChunks(String dbName, List<String> texts, {String source = ''}) async {
    _logService.log('KeywordDbService', 'Appending ${texts.length} chunks to: $dbName');
    final db = await _getDb();

    // Get current max index
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(chunk_idx), -1) as max_idx FROM chunks WHERE db_name = ?',
      [dbName],
    );
    final startIdx = (Sqflite.firstIntValue(result) ?? -1) + 1;

    final batch = db.batch();
    for (var i = 0; i < texts.length; i++) {
      batch.insert('chunks', {
        'db_name': dbName,
        'chunk_idx': startIdx + i,
        'text': texts[i],
        'source': source,
      });
    }
    await batch.commit(noResult: true);
    _logService.log('KeywordDbService', 'Appended ${texts.length} chunks starting at index $startIdx');
  }

  /// Search all chunks across specified DBs using keyword search.
  static Future<List<KeywordSearchResult>> search({
    required String query,
    List<String>? dbNames,
    int topK = 5,
  }) async {
    _logService.log('KeywordDbService', 'Searching with query: "${query.length > 80 ? query.substring(0, 80) + "..." : query}"');
    final db = await _getDb();

    // Determine which DBs to search
    List<String> targetDbs;
    if (dbNames != null && dbNames.isNotEmpty) {
      targetDbs = dbNames;
    } else {
      targetDbs = await listDbs();
    }

    if (targetDbs.isEmpty) {
      _logService.log('KeywordDbService', 'No keyword DBs to search');
      return [];
    }

    // Load all chunks from target DBs
    final allChunks = <KeywordChunk>[];
    for (final dbName in targetDbs) {
      final rows = await db.query(
        'chunks',
        where: 'db_name = ?',
        whereArgs: [dbName],
        orderBy: 'chunk_idx ASC',
      );
      for (final row in rows) {
        allChunks.add(KeywordChunk(
          id: row['chunk_idx'] as int,
          text: row['text'] as String,
          dbName: dbName,
          source: row['source'] as String? ?? '',
        ));
      }
      _logService.log('KeywordDbService', '  Loaded ${rows.length} chunks from $dbName');
    }

    _logService.log('KeywordDbService', 'Total chunks across ${targetDbs.length} DBs: ${allChunks.length}');

    // Run BM25 keyword search with diversity re-ranking
    final results = KeywordSearchEngine.search(
      query: query,
      chunks: allChunks,
      topK: topK,
    );

    _logService.log('KeywordDbService', 'Search returned ${results.length} results');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      _logService.log('KeywordDbService', '  Result[$i]: score=${r.score.toStringAsFixed(4)} db=${r.dbName} chunkId=${r.chunkId}');
    }

    return results;
  }

  /// Delete all chunks for a DB.
  static Future<void> deleteDb(String dbName) async {
    _logService.log('KeywordDbService', 'Deleting DB: $dbName');
    final db = await _getDb();
    await db.delete('chunks', where: 'db_name = ?', whereArgs: [dbName]);
  }

  /// Load all chunks for a DB (for UI display).
  static Future<List<Map<String, dynamic>>> loadChunks(String dbName) async {
    final db = await _getDb();
    return db.query(
      'chunks',
      where: 'db_name = ?',
      whereArgs: [dbName],
      orderBy: 'chunk_idx ASC',
    );
  }

  /// Close the database.
  static Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
