import 'package:objectbox/objectbox.dart';

@Entity()
class VectorChunk {
  @Id()
  int id;

  @Property(type: PropertyType.string)
  String text;

  @Property(type: PropertyType.floatVector)
  List<double> embedding;

  @Property(type: PropertyType.string)
  String source;

  @Property(type: PropertyType.long)
  int createdAt;

  VectorChunk({
    this.id = 0,
    required this.text,
    required this.embedding,
    this.source = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;
}
