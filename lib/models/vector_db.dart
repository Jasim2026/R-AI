class VectorDb {
  final String name;
  final String filePath;
  final int chunkCount;
  final int embeddingDimension;
  final DateTime createdAt;
  final DateTime modifiedAt;

  VectorDb({
    required this.name,
    required this.filePath,
    this.chunkCount = 0,
    this.embeddingDimension = 0,
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  VectorDb copyWith({
    String? name,
    int? chunkCount,
    int? embeddingDimension,
    DateTime? modifiedAt,
  }) {
    return VectorDb(
      name: name ?? this.name,
      filePath: filePath,
      chunkCount: chunkCount ?? this.chunkCount,
      embeddingDimension: embeddingDimension ?? this.embeddingDimension,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }

  String get displayName => name.replaceAll('.db', '');
}
