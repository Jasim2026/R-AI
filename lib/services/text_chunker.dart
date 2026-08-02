class TextChunker {
  final int chunkSize;
  final int overlap;
  final String? delimiter;

  const TextChunker({
    this.chunkSize = 500,
    this.overlap = 50,
    this.delimiter,
  });

  List<String> chunk(String text) {
    if (text.trim().isEmpty) return [];

    final clean = text.trim();
    if (clean.length <= chunkSize) return [clean];

    if (delimiter != null) {
      return _chunkByDelimiter(clean);
    }
    return _chunkByCharacter(clean);
  }

  List<String> _chunkByCharacter(String text) {
    final chunks = <String>[];
    var start = 0;

    while (start < text.length) {
      var end = start + chunkSize;

      if (end < text.length) {
        final lastSpace = text.lastIndexOf(' ', end);
        final lastNewline = text.lastIndexOf('\n', end);
        final breakPoint = lastSpace > lastNewline ? lastSpace : lastNewline;

        if (breakPoint > start + chunkSize * 0.5) {
          end = breakPoint + 1;
        }
      } else {
        end = text.length;
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      start = end - overlap;
      if (start >= text.length) break;
    }

    return chunks;
  }

  List<String> _chunkByDelimiter(String text) {
    final chunks = <String>[];
    final segments = text.split(delimiter!);
    final buffer = StringBuffer();
    var currentLen = 0;

    for (final segment in segments) {
      final segLen = segment.length;
      if (currentLen + segLen > chunkSize && currentLen > 0) {
        final chunk = buffer.toString().trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        buffer.clear();
        currentLen = 0;
      }

      if (currentLen > 0) {
        buffer.write(delimiter);
        currentLen += delimiter!.length;
      }
      buffer.write(segment);
      currentLen += segLen;
    }

    if (buffer.isNotEmpty) {
      final chunk = buffer.toString().trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
    }

    return chunks;
  }
}
