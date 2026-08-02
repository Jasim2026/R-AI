class VectorChunk {
  final int id;
  final String text;
  final List<double> vector;
  final String source;
  final DateTime createdAt;

  VectorChunk({
    required this.id,
    required this.text,
    required this.vector,
    this.source = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get dimension => vector.length;
}
