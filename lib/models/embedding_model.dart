import 'package:uuid/uuid.dart';

class EmbeddingModel {
  final String id;
  final String name;
  final String path;
  final String? description;
  final int dimensions;
  final DateTime importedAt;

  EmbeddingModel({
    String? id,
    required this.name,
    required this.path,
    this.description,
    this.dimensions = 384,
    DateTime? importedAt,
  })  : id = id ?? const Uuid().v4(),
        importedAt = importedAt ?? DateTime.now();

  EmbeddingModel copyWith({
    String? name,
    String? path,
    String? description,
    int? dimensions,
  }) {
    return EmbeddingModel(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      description: description ?? this.description,
      dimensions: dimensions ?? this.dimensions,
      importedAt: importedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'description': description,
      'dimensions': dimensions,
      'importedAt': importedAt.toIso8601String(),
    };
  }

  factory EmbeddingModel.fromMap(Map<String, dynamic> map) {
    return EmbeddingModel(
      id: map['id'],
      name: map['name'],
      path: map['path'],
      description: map['description'],
      dimensions: map['dimensions'] ?? 384,
      importedAt: DateTime.parse(map['importedAt']),
    );
  }
}
