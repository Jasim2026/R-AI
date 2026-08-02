import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/vector_chunk.dart';
import '../models/vector_db.dart';
import 'log_service.dart';

class VectorDbService {
  static const _magic = 0x52414956; // "RAIV" in hex
  static const _version = 1;
  static const _headerSize = 24; // magic(4) + version(4) + chunkCount(4) + dim(4) + reserved(8)
  static final LogService _logService = LogService();

  static Future<String> get _vectorsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/vectors');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> _dbPath(String name) async {
    final dir = await _vectorsDir;
    final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
    final dbName = safeName.endsWith('.db') ? safeName : '$safeName.db';
    return '$dir/$dbName';
  }

  static Future<VectorDb> createDb(String name, int embeddingDimension) async {
    _logService.log('VectorDbService', 'Creating database: $name, dim=$embeddingDimension');
    final path = await _dbPath(name);
    _logService.log('VectorDbService', 'DB path: $path');
    final file = File(path);

    final header = ByteData(_headerSize);
    header.setUint32(0, _magic, Endian.little);
    header.setUint32(4, _version, Endian.little);
    header.setUint32(8, 0, Endian.little); // chunkCount = 0
    header.setUint32(12, embeddingDimension, Endian.little);
    // bytes 16-23 reserved

    await file.writeAsBytes(header.buffer.asUint8List());
    _logService.log('VectorDbService', 'Database created: $path (${_headerSize} bytes header)');

    return VectorDb(
      name: name,
      filePath: path,
      chunkCount: 0,
      embeddingDimension: embeddingDimension,
    );
  }

  static Future<VectorDb?> openDb(String name) async {
    _logService.log('VectorDbService', 'Opening database: $name');
    final path = await _dbPath(name);
    final file = File(path);
    if (!await file.exists()) {
      _logService.log('VectorDbService', 'Database file not found: $path');
      return null;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) {
      _logService.log('VectorDbService', 'ERROR: File too small for header: ${bytes.length} bytes');
      return null;
    }

    final magic = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    if (magic != _magic) {
      _logService.log('VectorDbService', 'ERROR: Invalid magic number: 0x${magic.toRadixString(16)} (expected 0x${_magic.toRadixString(16)})');
      return null;
    }

    final chunkCount = ByteData.sublistView(bytes).getUint32(8, Endian.little);
    final dim = ByteData.sublistView(bytes).getUint32(12, Endian.little);
    _logService.log('VectorDbService', 'Database opened: chunks=$chunkCount, dim=$dim');

    return VectorDb(
      name: name,
      filePath: path,
      chunkCount: chunkCount,
      embeddingDimension: dim,
    );
  }

  static Future<List<VectorDb>> listDbs() async {
    _logService.log('VectorDbService', 'Listing databases...');
    final dir = await _vectorsDir;
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.db'));
    final dbs = <VectorDb>[];

    _logService.log('VectorDbService', 'Found ${files.length} .db files');
    for (final file in files) {
      try {
        final name = file.path.split('/').last.replaceAll('.db', '');
        final db = await openDb(name);
        if (db != null) {
          dbs.add(db);
          _logService.log('VectorDbService', '  DB: ${db.name} | chunks: ${db.chunkCount} | dim: ${db.embeddingDimension} | size: ${file.lengthSync()} bytes');
        }
      } catch (e) {
        _logService.logError('VectorDbService', 'Error reading DB: ${file.path}', e, null);
      }
    }

    _logService.log('VectorDbService', 'Total databases: ${dbs.length}');
    return dbs;
  }

  static Future<void> addChunks(String dbPath, List<String> texts, List<List<double>> vectors) async {
    _logService.log('VectorDbService', 'Adding ${texts.length} chunks to: $dbPath');
    if (texts.isEmpty || texts.length != vectors.length) {
      _logService.log('VectorDbService', 'ERROR: texts/vectors mismatch: texts=${texts.length}, vectors=${vectors.length}');
      return;
    }

    final file = File(dbPath);
    final existing = await file.readAsBytes();
    final header = ByteData.sublistView(existing);

    final oldCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);
    _logService.log('VectorDbService', 'Existing: $oldCount chunks, dim=$dim');

    // Validate dimensions
    for (var i = 0; i < vectors.length; i++) {
      if (vectors[i].length != dim) {
        _logService.log('VectorDbService', 'ERROR: Vector dimension mismatch at index $i: expected $dim, got ${vectors[i].length}');
        throw ArgumentError('Vector dimension mismatch: expected $dim, got ${vectors[i].length}');
      }
    }

    // Build metadata section (text lengths + texts + sources)
    final metaBuffer = BytesBuilder();
    var totalMetaBytes = 0;
    for (final text in texts) {
      final textBytes = Uint8List.fromList(text.codeUnits);
      final lenBytes = ByteData(4);
      lenBytes.setUint32(0, textBytes.length, Endian.little);
      metaBuffer.add(lenBytes.buffer.asUint8List());
      metaBuffer.add(textBytes);
      totalMetaBytes += 4 + textBytes.length;
    }
    _logService.log('VectorDbService', 'Metadata section: $totalMetaBytes bytes for ${texts.length} texts');

    // Build vector section
    final vecBuffer = BytesBuilder();
    for (final vec in vectors) {
      final float32 = Float32List(vec.length);
      for (var i = 0; i < vec.length; i++) {
        float32[i] = vec[i];
      }
      vecBuffer.add(float32.buffer.asUint8List());
    }
    final totalVecBytes = vectors.length * dim * 4;
    _logService.log('VectorDbService', 'Vector section: $totalVecBytes bytes (${vectors.length} vectors x $dim floats x 4 bytes)');

    // Write: keep header, append metadata, append vectors
    _logService.log('VectorDbService', 'Writing to file...');
    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    sink.add(metaBuffer.toBytes());
    sink.add(vecBuffer.toBytes());
    await sink.flush();
    await sink.close();

    // Update header with new chunk count
    header.setUint32(8, oldCount + texts.length, Endian.little);
    final updated = header.buffer.asUint8List();

    // Rewrite just the header
    final raf = await file.open(mode: FileMode.writeOnly);
    await raf.writeFrom(updated, 0, _headerSize);
    await raf.close();

    _logService.log('VectorDbService', 'Chunks added successfully. New total: ${oldCount + texts.length} chunks');
  }

  static Future<List<VectorChunk>> loadChunks(String dbPath, {int? limit, int offset = 0}) async {
    _logService.log('VectorDbService', 'Loading chunks from: $dbPath (offset=$offset, limit=$limit)');
    final file = File(dbPath);
    if (!await file.exists()) {
      _logService.log('VectorDbService', 'ERROR: File not found: $dbPath');
      return [];
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) {
      _logService.log('VectorDbService', 'ERROR: File too small: ${bytes.length} bytes');
      return [];
    }

    final header = ByteData.sublistView(bytes);
    final chunkCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);
    _logService.log('VectorDbService', 'DB header: chunks=$chunkCount, dim=$dim');

    if (chunkCount == 0) {
      _logService.log('VectorDbService', 'No chunks in database');
      return [];
    }

    // Parse metadata section
    var pos = _headerSize;
    final texts = <String>[];
    for (var i = 0; i < chunkCount; i++) {
      if (pos + 4 > bytes.length) {
        _logService.log('VectorDbService', 'WARNING: Truncated metadata at chunk $i');
        break;
      }
      final textLen = ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.little);
      pos += 4;
      if (pos + textLen > bytes.length) {
        _logService.log('VectorDbService', 'WARNING: Truncated text at chunk $i (expected $textLen bytes)');
        break;
      }
      final textBytes = bytes.sublist(pos, pos + textLen);
      texts.add(String.fromCharCodes(textBytes));
      pos += textLen;
    }
    _logService.log('VectorDbService', 'Parsed ${texts.length} text entries');

    // Return chunks with text only (no vectors loaded for efficiency)
    final end = limit != null ? min(offset + limit, chunkCount) : chunkCount;
    final result = <VectorChunk>[];
    for (var i = offset; i < end; i++) {
      result.add(VectorChunk(
        id: i,
        text: i < texts.length ? texts[i] : '',
        vector: [],
        source: '',
      ));
    }

    _logService.log('VectorDbService', 'Returning ${result.length} chunks (offset=$offset, limit=$limit)');
    return result;
  }

  static Future<List<VectorChunk>> loadChunksForSearch(String dbPath) async {
    _logService.log('VectorDbService', 'Loading chunks for search from: $dbPath');
    final file = File(dbPath);
    if (!await file.exists()) {
      _logService.log('VectorDbService', 'ERROR: File not found: $dbPath');
      return [];
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) {
      _logService.log('VectorDbService', 'ERROR: File too small: ${bytes.length} bytes');
      return [];
    }

    final header = ByteData.sublistView(bytes);
    final chunkCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);
    _logService.log('VectorDbService', 'DB header: chunks=$chunkCount, dim=$dim');

    if (chunkCount == 0) {
      _logService.log('VectorDbService', 'No chunks in database');
      return [];
    }

    // Parse metadata
    var pos = _headerSize;
    final texts = <String>[];
    for (var i = 0; i < chunkCount; i++) {
      if (pos + 4 > bytes.length) break;
      final textLen = ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.little);
      pos += 4;
      if (pos + textLen > bytes.length) break;
      texts.add(String.fromCharCodes(bytes.sublist(pos, pos + textLen)));
      pos += textLen;
    }

    // Parse vectors
    final vecStart = pos;
    final chunks = <VectorChunk>[];
    for (var i = 0; i < chunkCount; i++) {
      final vecOffset = vecStart + (i * dim * 4);
      if (vecOffset + dim * 4 > bytes.length) {
        _logService.log('VectorDbService', 'WARNING: Truncated vector at chunk $i');
        break;
      }

      final float32 = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes + vecOffset,
        dim,
      );
      final vec = List<double>.from(float32);

      chunks.add(VectorChunk(
        id: i,
        text: i < texts.length ? texts[i] : '',
        vector: vec,
      ));
    }

    _logService.log('VectorDbService', 'Loaded ${chunks.length} chunks with vectors for search');
    return chunks;
  }

  static Future<void> editText(String dbPath, int chunkId, String newText) async {
    _logService.log('VectorDbService', 'Editing chunk $chunkId in: $dbPath');
    _logService.log('VectorDbService', 'New text: "${newText.length > 80 ? newText.substring(0, 80) + "..." : newText}"');
    final file = File(dbPath);
    if (!await file.exists()) {
      _logService.log('VectorDbService', 'ERROR: File not found: $dbPath');
      return;
    }

    final chunks = await loadChunksForSearch(dbPath);
    if (chunkId < 0 || chunkId >= chunks.length) {
      _logService.log('VectorDbService', 'ERROR: Invalid chunk ID: $chunkId (max: ${chunks.length - 1})');
      return;
    }

    // Rebuild the entire file with updated text
    final dim = chunks.isNotEmpty ? chunks.first.dimension : 0;
    final tempPath = '$dbPath.tmp';
    final tempFile = File(tempPath);

    // Write header
    final header = ByteData(_headerSize);
    header.setUint32(0, _magic, Endian.little);
    header.setUint32(4, _version, Endian.little);
    header.setUint32(8, chunks.length, Endian.little);
    header.setUint32(12, dim, Endian.little);

    final sink = tempFile.openWrite();
    sink.add(header.buffer.asUint8List());

    // Write metadata
    for (var i = 0; i < chunks.length; i++) {
      final text = i == chunkId ? newText : chunks[i].text;
      final textBytes = Uint8List.fromList(text.codeUnits);
      final lenBytes = ByteData(4);
      lenBytes.setUint32(0, textBytes.length, Endian.little);
      sink.add(lenBytes.buffer.asUint8List());
      sink.add(textBytes);
    }

    // Write vectors
    for (final chunk in chunks) {
      final float32 = Float32List(chunk.vector.length);
      for (var i = 0; i < chunk.vector.length; i++) {
        float32[i] = chunk.vector[i];
      }
      sink.add(float32.buffer.asUint8List());
    }

    await sink.flush();
    await sink.close();
    await tempFile.rename(dbPath);
    _logService.log('VectorDbService', 'Chunk $chunkId edited successfully');
  }

  static Future<void> addTexts(String dbPath, List<String> texts) async {
    // Placeholder: texts need to be embedded before adding
    // This is called after embedding to store the vectors
    // The actual embedding happens in the provider layer
    throw UnimplementedError('Use addChunks() after embedding texts');
  }

  static Future<void> deleteChunks(String dbPath, List<int> chunkIds) async {
    _logService.log('VectorDbService', 'Deleting ${chunkIds.length} chunks from: $dbPath');
    final chunks = await loadChunksForSearch(dbPath);
    if (chunks.isEmpty) {
      _logService.log('VectorDbService', 'No chunks to delete');
      return;
    }

    final toDelete = Set<int>.from(chunkIds);
    final remaining = <VectorChunk>[];

    for (final chunk in chunks) {
      if (!toDelete.contains(chunk.id)) {
        remaining.add(chunk);
      }
    }

    _logService.log('VectorDbService', 'After deletion: ${remaining.length} chunks remaining');

    if (remaining.isEmpty) {
      _logService.log('VectorDbService', 'All chunks deleted, removing file');
      await File(dbPath).delete();
      return;
    }

    // Rebuild file with remaining chunks
    final dim = chunks.first.dimension;
    final tempPath = '$dbPath.tmp';
    final tempFile = File(tempPath);

    final header = ByteData(_headerSize);
    header.setUint32(0, _magic, Endian.little);
    header.setUint32(4, _version, Endian.little);
    header.setUint32(8, remaining.length, Endian.little);
    header.setUint32(12, dim, Endian.little);

    final sink = tempFile.openWrite();
    sink.add(header.buffer.asUint8List());

    for (final chunk in remaining) {
      final textBytes = Uint8List.fromList(chunk.text.codeUnits);
      final lenBytes = ByteData(4);
      lenBytes.setUint32(0, textBytes.length, Endian.little);
      sink.add(lenBytes.buffer.asUint8List());
      sink.add(textBytes);
    }

    for (final chunk in remaining) {
      final float32 = Float32List(chunk.vector.length);
      for (var i = 0; i < chunk.vector.length; i++) {
        float32[i] = chunk.vector[i];
      }
      sink.add(float32.buffer.asUint8List());
    }

    await sink.flush();
    await sink.close();
    await tempFile.rename(dbPath);
    _logService.log('VectorDbService', 'Chunks deleted and file rebuilt');
  }

  static Future<void> deleteDb(String name) async {
    _logService.log('VectorDbService', 'Deleting database: $name');
    final path = await _dbPath(name);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _logService.log('VectorDbService', 'Database deleted: $path');
    } else {
      _logService.log('VectorDbService', 'Database file not found: $path');
    }
  }

  static Future<List<VectorSearchResult>> search({
    required List<String> dbPaths,
    required List<double> queryVector,
    int topK = 5,
    double minScore = 0.3,
  }) async {
    _logService.log('VectorDbService', 'Searching ${dbPaths.length} databases');
    _logService.log('VectorDbService', 'Query vector dim: ${queryVector.length}, topK=$topK, minScore=$minScore');
    final results = <VectorSearchResult>[];

    for (final dbPath in dbPaths) {
      _logService.log('VectorDbService', 'Searching DB: ${dbPath.split('/').last}');
      try {
        final chunks = await loadChunksForSearch(dbPath);
        _logService.log('VectorDbService', 'Loaded ${chunks.length} chunks for search');
        var matchCount = 0;
        for (final chunk in chunks) {
          if (chunk.vector.isEmpty) continue;
          final score = _cosineSimilarity(queryVector, chunk.vector);
          if (score >= minScore) {
            matchCount++;
            results.add(VectorSearchResult(
              chunkId: chunk.id,
              text: chunk.text,
              score: score,
              dbPath: dbPath,
            ));
          }
        }
        _logService.log('VectorDbService', 'DB ${dbPath.split('/').last}: $matchCount matches above threshold');
      } catch (e) {
        _logService.logError('VectorDbService', 'Error searching DB: $dbPath', e, null);
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    final finalResults = results.length > topK ? results.sublist(0, topK) : results;
    _logService.log('VectorDbService', 'Search complete: ${finalResults.length} results (total matches: ${results.length})');
    for (var i = 0; i < finalResults.length; i++) {
      final r = finalResults[i];
      _logService.log('VectorDbService', '  Result[$i]: score=${r.score.toStringAsFixed(4)} db=${r.dbPath.split('/').last} chunkId=${r.chunkId}');
    }
    return finalResults;
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    return denom == 0 ? 0 : dot / denom;
  }
}

class VectorSearchResult {
  final int chunkId;
  final String text;
  final double score;
  final String dbPath;

  VectorSearchResult({
    required this.chunkId,
    required this.text,
    required this.score,
    required this.dbPath,
  });
}
