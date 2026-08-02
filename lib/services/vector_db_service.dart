import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/vector_chunk.dart';
import '../models/vector_db.dart';

class VectorDbService {
  static const _magic = 0x52414956; // "RAIV" in hex
  static const _version = 1;
  static const _headerSize = 24; // magic(4) + version(4) + chunkCount(4) + dim(4) + reserved(8)

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
    final path = await _dbPath(name);
    final file = File(path);

    final header = ByteData(_headerSize);
    header.setUint32(0, _magic, Endian.little);
    header.setUint32(4, _version, Endian.little);
    header.setUint32(8, 0, Endian.little); // chunkCount = 0
    header.setUint32(12, embeddingDimension, Endian.little);
    // bytes 16-23 reserved

    await file.writeAsBytes(header.buffer.asUint8List());

    return VectorDb(
      name: name,
      filePath: path,
      chunkCount: 0,
      embeddingDimension: embeddingDimension,
    );
  }

  static Future<VectorDb?> openDb(String name) async {
    final path = await _dbPath(name);
    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) return null;

    final magic = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    if (magic != _magic) return null;

    final chunkCount = ByteData.sublistView(bytes).getUint32(8, Endian.little);
    final dim = ByteData.sublistView(bytes).getUint32(12, Endian.little);

    return VectorDb(
      name: name,
      filePath: path,
      chunkCount: chunkCount,
      embeddingDimension: dim,
    );
  }

  static Future<List<VectorDb>> listDbs() async {
    final dir = await _vectorsDir;
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.db'));
    final dbs = <VectorDb>[];

    for (final file in files) {
      try {
        final name = file.path.split('/').last.replaceAll('.db', '');
        final db = await openDb(name);
        if (db != null) dbs.add(db);
      } catch (_) {}
    }

    return dbs;
  }

  static Future<void> addChunks(String dbPath, List<String> texts, List<List<double>> vectors) async {
    if (texts.isEmpty || texts.length != vectors.length) return;

    final file = File(dbPath);
    final existing = await file.readAsBytes();
    final header = ByteData.sublistView(existing);

    final oldCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);

    // Validate dimensions
    for (final v in vectors) {
      if (v.length != dim) throw ArgumentError('Vector dimension mismatch: expected $dim, got ${v.length}');
    }

    // Build metadata section (text lengths + texts + sources)
    final metaBuffer = BytesBuilder();
    for (final text in texts) {
      final textBytes = Uint8List.fromList(text.codeUnits);
      final lenBytes = ByteData(4);
      lenBytes.setUint32(0, textBytes.length, Endian.little);
      metaBuffer.add(lenBytes.buffer.asUint8List());
      metaBuffer.add(textBytes);
    }

    // Build vector section
    final vecBuffer = BytesBuilder();
    for (final vec in vectors) {
      final float32 = Float32List(vec.length);
      for (var i = 0; i < vec.length; i++) {
        float32[i] = vec[i];
      }
      vecBuffer.add(float32.buffer.asUint8List());
    }

    // Write: keep header, append metadata, append vectors
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
  }

  static Future<List<VectorChunk>> loadChunks(String dbPath, {int? limit, int offset = 0}) async {
    final file = File(dbPath);
    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) return [];

    final header = ByteData.sublistView(bytes);
    final chunkCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);

    if (chunkCount == 0) return [];

    // Parse metadata section
    var pos = _headerSize;
    final texts = <String>[];
    for (var i = 0; i < chunkCount; i++) {
      if (pos + 4 > bytes.length) break;
      final textLen = ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.little);
      pos += 4;
      if (pos + textLen > bytes.length) break;
      final textBytes = bytes.sublist(pos, pos + textLen);
      texts.add(String.fromCharCodes(textBytes));
      pos += textLen;
    }

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

    return result;
  }

  static Future<List<VectorChunk>> loadChunksForSearch(String dbPath) async {
    final file = File(dbPath);
    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    if (bytes.length < _headerSize) return [];

    final header = ByteData.sublistView(bytes);
    final chunkCount = header.getUint32(8, Endian.little);
    final dim = header.getUint32(12, Endian.little);

    if (chunkCount == 0) return [];

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
      if (vecOffset + dim * 4 > bytes.length) break;

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

    return chunks;
  }

  static Future<void> editText(String dbPath, int chunkId, String newText) async {
    final file = File(dbPath);
    if (!await file.exists()) return;

    final chunks = await loadChunksForSearch(dbPath);
    if (chunkId < 0 || chunkId >= chunks.length) return;

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
  }

  static Future<void> addTexts(String dbPath, List<String> texts) async {
    // Placeholder: texts need to be embedded before adding
    // This is called after embedding to store the vectors
    // The actual embedding happens in the provider layer
    throw UnimplementedError('Use addChunks() after embedding texts');
  }

  static Future<void> deleteChunks(String dbPath, List<int> chunkIds) async {
    final chunks = await loadChunksForSearch(dbPath);
    if (chunks.isEmpty) return;

    final toDelete = Set<int>.from(chunkIds);
    final remaining = <VectorChunk>[];

    for (final chunk in chunks) {
      if (!toDelete.contains(chunk.id)) {
        remaining.add(chunk);
      }
    }

    if (remaining.isEmpty) {
      // Delete entire file
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
  }

  static Future<void> deleteDb(String name) async {
    final path = await _dbPath(name);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<List<VectorSearchResult>> search({
    required List<String> dbPaths,
    required List<double> queryVector,
    int topK = 5,
    double minScore = 0.3,
  }) async {
    final results = <VectorSearchResult>[];

    for (final dbPath in dbPaths) {
      try {
        final chunks = await loadChunksForSearch(dbPath);
        for (final chunk in chunks) {
          if (chunk.vector.isEmpty) continue;
          final score = _cosineSimilarity(queryVector, chunk.vector);
          if (score >= minScore) {
            results.add(VectorSearchResult(
              chunkId: chunk.id,
              text: chunk.text,
              score: score,
              dbPath: dbPath,
            ));
          }
        }
      } catch (_) {}
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.length > topK ? results.sublist(0, topK) : results;
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
