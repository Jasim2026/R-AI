import 'package:uuid/uuid.dart';

enum BackendType { cpu, gpu, npu }

class LLMModel {
  final String id;
  final String name;
  final String path;
  final String? description;
  final int? parameterSize;
  final BackendType backend;
  final List<BackendType> supportedBackends;
  final String? detectedParams;
  final String? cacheDir;
  final DateTime importedAt;
  final bool isDefault;

  LLMModel({
    String? id,
    required this.name,
    required this.path,
    this.description,
    this.parameterSize,
    this.backend = BackendType.gpu,
    this.supportedBackends = const [],
    this.detectedParams,
    this.cacheDir,
    DateTime? importedAt,
    this.isDefault = false,
  })  : id = id ?? const Uuid().v4(),
        importedAt = importedAt ?? DateTime.now();

  LLMModel copyWith({
    String? name,
    String? path,
    String? description,
    int? parameterSize,
    BackendType? backend,
    List<BackendType>? supportedBackends,
    String? detectedParams,
    String? cacheDir,
    bool? isDefault,
  }) {
    return LLMModel(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      description: description ?? this.description,
      parameterSize: parameterSize ?? this.parameterSize,
      backend: backend ?? this.backend,
      supportedBackends: supportedBackends ?? this.supportedBackends,
      detectedParams: detectedParams ?? this.detectedParams,
      cacheDir: cacheDir ?? this.cacheDir,
      importedAt: importedAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  String get backendName {
    switch (backend) {
      case BackendType.cpu:
        return 'CPU';
      case BackendType.gpu:
        return 'GPU';
      case BackendType.npu:
        return 'NPU';
    }
  }

  String get parameterLabel {
    if (parameterSize == null) return 'Unknown';
    if (parameterSize! >= 1000) return '${(parameterSize! / 1000).toStringAsFixed(1)}T';
    return '${parameterSize}B';
  }

  bool get isLiteRTLM => path.endsWith('.litertlm');

  bool get hasMetadata => supportedBackends.isNotEmpty;

  BackendType get autoSelectedBackend {
    if (supportedBackends.isEmpty) return backend;
    if (supportedBackends.contains(BackendType.gpu)) return BackendType.gpu;
    if (supportedBackends.contains(BackendType.npu)) return BackendType.npu;
    return BackendType.cpu;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'description': description,
      'parameterSize': parameterSize,
      'backend': backend.name,
      'supportedBackends': supportedBackends.map((b) => b.name).toList(),
      'detectedParams': detectedParams,
      'cacheDir': cacheDir,
      'importedAt': importedAt.toIso8601String(),
      'isDefault': isDefault,
    };
  }

  factory LLMModel.fromMap(Map<String, dynamic> map) {
    return LLMModel(
      id: map['id'],
      name: map['name'],
      path: map['path'],
      description: map['description'],
      parameterSize: map['parameterSize'],
      backend: BackendType.values.firstWhere(
        (e) => e.name == map['backend'],
        orElse: () => BackendType.gpu,
      ),
      supportedBackends: (map['supportedBackends'] as List?)
              ?.map((b) => BackendType.values.firstWhere(
                    (e) => e.name == b,
                    orElse: () => BackendType.gpu,
                  ))
              .toList() ??
          [],
      detectedParams: map['detectedParams'],
      cacheDir: map['cacheDir'],
      importedAt: DateTime.parse(map['importedAt']),
      isDefault: map['isDefault'] ?? false,
    );
  }
}