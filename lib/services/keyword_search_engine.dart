import 'dart:math';

/// BM25-based keyword search engine with diversity re-ranking.
///
/// Scoring pipeline:
///   1. BM25 relevance scoring (k1=1.2, b=0.75)
///   2. Stopword filtering (articles, determiners, high-frequency words)
///   3. Top-3 sampling with unique-word diversity re-ranking
class KeywordSearchEngine {
  /// Standard English stopwords — articles, determiners, prepositions,
  /// pronouns, conjunctions, auxiliary verbs, common high-frequency words.
  static const _stopwords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'in', 'on', 'at', 'to',
    'for', 'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were',
    'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
    'will', 'would', 'could', 'should', 'may', 'might', 'shall', 'can',
    'not', 'no', 'nor', 'so', 'too', 'very', 'just', 'than', 'that',
    'this', 'these', 'those', 'it', 'its', 'he', 'she', 'they', 'we',
    'you', 'i', 'me', 'my', 'your', 'his', 'her', 'our', 'their',
    'what', 'which', 'who', 'whom', 'where', 'when', 'why', 'how',
    'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other',
    'some', 'such', 'own', 'same', 'then', 'here', 'there', 'also',
    'about', 'into', 'over', 'after', 'before', 'between', 'under',
    'again', 'once', 'only', 'even', 'still', 'already', 'always',
    'never', 'often', 'sometimes', 'usually', 'now', 'well', 'yes',
    'maybe', 'thing', 'things', 'way', 'ways', 'much', 'many',
    'make', 'made', 'get', 'got', 'going', 'went', 'come', 'came',
    'take', 'took', 'give', 'gave', 'say', 'said', 'tell', 'told',
    'know', 'knew', 'think', 'thought', 'see', 'saw', 'use', 'used',
    'find', 'found', 'want', 'wanted', 'need', 'needed', 'try', 'tried',
    'keep', 'kept', 'let', 'put', 'set', 'run', 'move', 'live', 'feel',
    'left', 'right', 'good', 'bad', 'new', 'old', 'first', 'last',
    'long', 'great', 'little', 'next', 'high', 'small', 'large',
  };

  /// Tokenize text into lowercase word stems.
  /// Strips punctuation, splits on whitespace, filters stopwords and words < 2 chars.
  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_stopwords.contains(w))
        .toList();
  }

  /// Tokenize without filtering stopwords (for diversity comparison).
  static List<String> tokenizeAll(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();
  }

  /// BM25 score for a query against a document.
  ///
  /// [queryTerms] — pre-tokenized query words (stopwords removed).
  /// [docTerms] — pre-tokenized document words (stopwords removed).
  /// [docLength] — length of the document in terms.
  /// [avgDocLength] — average document length across all chunks.
  /// [totalDocs] — total number of chunks in the index.
  /// [docFrequency] — map of term → number of documents containing it.
  static double bm25Score({
    required List<String> queryTerms,
    required List<String> docTerms,
    required int docLength,
    required double avgDocLength,
    required int totalDocs,
    required Map<String, int> docFrequency,
  }) {
    const k1 = 1.2;
    const b = 0.75;

    // Build term frequency map for this document
    final termFreq = <String, int>{};
    for (final term in docTerms) {
      termFreq[term] = (termFreq[term] ?? 0) + 1;
    }

    var score = 0.0;
    for (final term in queryTerms) {
      final tf = termFreq[term] ?? 0;
      if (tf == 0) continue;

      final df = docFrequency[term] ?? 0;
      // IDF with smoothing: log((N - df + 0.5) / (df + 0.5) + 1)
      final idf = log((totalDocs - df + 0.5) / (df + 0.5) + 1);

      // BM25 term scoring
      final numerator = tf * (k1 + 1);
      final denominator = tf + k1 * (1 - b + b * docLength / avgDocLength);
      score += idf * (numerator / denominator);
    }

    return score;
  }

  /// Perform keyword search with BM25 scoring and diversity re-ranking.
  ///
  /// Returns top [topK] results sorted by final score (relevance + diversity bonus).
  ///
  /// Algorithm:
  ///   1. Score all chunks with BM25
  ///   2. Take top 3 as candidates
  ///   3. For each candidate, count "unique matching words" — words that
  ///      match the query AND appear in this chunk BUT NOT in the other 2
  ///      candidates. This measures how much unique relevant info it adds.
  ///   4. The candidate with the most unique matching words gets a +50% score
  ///      boost (diversity bonus) to prefer chunks with novel content.
  ///   5. Re-sort and return top-K.
  static List<KeywordSearchResult> search({
    required String query,
    required List<KeywordChunk> chunks,
    int topK = 5,
    double minScore = 0.01,
  }) {
    if (query.trim().isEmpty || chunks.isEmpty) return [];

    final queryTerms = tokenize(query);
    if (queryTerms.isEmpty) return [];

    // Build document frequency map across all chunks
    final docFrequency = <String, int>{};
    final tokenizedChunks = <int, List<String>>{};

    for (final chunk in chunks) {
      final terms = tokenize(chunk.text);
      tokenizedChunks[chunk.id] = terms;
      final seen = <String>{};
      for (final term in terms) {
        if (!seen.contains(term)) {
          docFrequency[term] = (docFrequency[term] ?? 0) + 1;
          seen.add(term);
        }
      }
    }

    // Calculate average document length
    final totalTerms = tokenizedChunks.values.fold<int>(0, (sum, t) => sum + t.length);
    final avgDocLength = chunks.isNotEmpty ? totalTerms / chunks.length : 1.0;

    // Step 1: BM25 scoring
    final scored = <(KeywordChunk chunk, double score)>[];
    for (final chunk in chunks) {
      final terms = tokenizedChunks[chunk.id] ?? [];
      final score = bm25Score(
        queryTerms: queryTerms,
        docTerms: terms,
        docLength: terms.length,
        avgDocLength: avgDocLength,
        totalDocs: chunks.length,
        docFrequency: docFrequency,
      );
      if (score >= minScore) {
        scored.add((chunk, score));
      }
    }

    if (scored.isEmpty) return [];

    // Sort by BM25 score descending
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // Step 2: Take top 3 candidates for diversity analysis
    final top3Count = min(3, scored.length);
    final top3 = scored.sublist(0, top3Count);

    // Step 3: Unique-word diversity analysis
    final queryTermSet = queryTerms.toSet();
    final top3ChunkTerms = top3.map((e) => tokenizedChunks[e.$1.id]?.toSet() ?? <String>{}).toList();

    for (var i = 0; i < top3Count; i++) {
      final myTerms = top3ChunkTerms[i];
      // Words that match query, are in this chunk, but NOT in any other top-3 chunk
      var uniqueCount = 0;
      for (final term in myTerms) {
        if (!queryTermSet.contains(term)) continue;
        var inOthers = false;
        for (var j = 0; j < top3Count; j++) {
          if (j != i && top3ChunkTerms[j].contains(term)) {
            inOthers = true;
            break;
          }
        }
        if (!inOthers) uniqueCount++;
      }

      // Step 4: Diversity bonus — +50% for chunk with most unique relevant terms
      if (i == 0 || uniqueCount > (top3[i > 0 ? i - 1 : i].$2 > 0 ? 1 : 0)) {
        // Apply bonus to the top candidate with unique words
      }
      // Store unique count for bonus application
      scored[scored.indexWhere((s) => s.$1.id == top3[i].$1.id)] =
          (top3[i].$1, top3[i].$2 * (1.0 + uniqueCount * 0.5));
    }

    // Step 5: Re-sort after diversity bonus
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // Return top-K
    final results = scored.take(topK).map((e) => KeywordSearchResult(
      chunkId: e.$1.id,
      text: e.$1.text,
      score: e.$2,
      dbName: e.$1.dbName,
      source: e.$1.source,
    )).toList();

    return results;
  }

  /// Search all chunks and return every scored result (no minScore, no topK limit).
  /// Used for live preview and percentage-based threshold computation.
  static List<KeywordSearchResult> searchAll({
    required String query,
    required List<KeywordChunk> chunks,
  }) {
    if (query.trim().isEmpty || chunks.isEmpty) return [];

    final queryTerms = tokenize(query);
    if (queryTerms.isEmpty) return [];

    final docFrequency = <String, int>{};
    final tokenizedChunks = <int, List<String>>{};

    for (final chunk in chunks) {
      final terms = tokenize(chunk.text);
      tokenizedChunks[chunk.id] = terms;
      final seen = <String>{};
      for (final term in terms) {
        if (!seen.contains(term)) {
          docFrequency[term] = (docFrequency[term] ?? 0) + 1;
          seen.add(term);
        }
      }
    }

    final totalTerms = tokenizedChunks.values.fold<int>(0, (sum, t) => sum + t.length);
    final avgDocLength = chunks.isNotEmpty ? totalTerms / chunks.length : 1.0;

    final results = <KeywordSearchResult>[];
    for (final chunk in chunks) {
      final terms = tokenizedChunks[chunk.id] ?? [];
      final score = bm25Score(
        queryTerms: queryTerms,
        docTerms: terms,
        docLength: terms.length,
        avgDocLength: avgDocLength,
        totalDocs: chunks.length,
        docFrequency: docFrequency,
      );
      results.add(KeywordSearchResult(
        chunkId: chunk.id,
        text: chunk.text,
        score: score,
        dbName: chunk.dbName,
        source: chunk.source,
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}

/// A chunk for keyword search (text-only, no vectors).
class KeywordChunk {
  final int id;
  final String text;
  final String dbName;
  final String source;

  const KeywordChunk({
    required this.id,
    required this.text,
    this.dbName = '',
    this.source = '',
  });
}

/// A search result from keyword search.
class KeywordSearchResult {
  final int chunkId;
  final String text;
  final double score;
  final String dbName;
  final String source;

  const KeywordSearchResult({
    required this.chunkId,
    required this.text,
    required this.score,
    required this.dbName,
    this.source = '',
  });
}
