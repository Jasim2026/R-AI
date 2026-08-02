import 'package:uuid/uuid.dart';

enum DetectionType { keyword, regex }

enum ExecutionType { websocket, native }

enum ToolCallStatus { idle, detected, executing, success, failed }

class ToolDefinition {
  final String id;
  String name;
  String description;
  String prompt;
  DetectionType detectionType;
  String detectionPattern;
  ExecutionType executionType;
  String websocketUrl;
  String websocketTrigger;
  String requestFormat;
  String responseFormat;
  String nativeAction;
  bool enabled;
  DateTime createdAt;

  ToolDefinition({
    String? id,
    this.name = '',
    this.description = '',
    this.prompt = '',
    this.detectionType = DetectionType.keyword,
    this.detectionPattern = '',
    this.executionType = ExecutionType.websocket,
    this.websocketUrl = '',
    this.websocketTrigger = '',
    this.requestFormat = '{"action": "{trigger}", "data": "{content}"}',
    this.responseFormat = '{"result": "..."}',
    this.nativeAction = '',
    this.enabled = true,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'prompt': prompt,
      'detectionType': detectionType.name,
      'detectionPattern': detectionPattern,
      'executionType': executionType.name,
      'websocketUrl': websocketUrl,
      'websocketTrigger': websocketTrigger,
      'requestFormat': requestFormat,
      'responseFormat': responseFormat,
      'nativeAction': nativeAction,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ToolDefinition.fromMap(Map<String, dynamic> map) {
    return ToolDefinition(
      id: map['id'],
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      prompt: map['prompt'] ?? '',
      detectionType: DetectionType.values.firstWhere(
        (e) => e.name == map['detectionType'],
        orElse: () => DetectionType.keyword,
      ),
      detectionPattern: map['detectionPattern'] ?? '',
      executionType: ExecutionType.values.firstWhere(
        (e) => e.name == map['executionType'],
        orElse: () => ExecutionType.websocket,
      ),
      websocketUrl: map['websocketUrl'] ?? '',
      websocketTrigger: map['websocketTrigger'] ?? '',
      requestFormat: map['requestFormat'] ?? '{"action": "{trigger}", "data": "{content}"}',
      responseFormat: map['responseFormat'] ?? '{"result": "..."}',
      nativeAction: map['nativeAction'] ?? '',
      enabled: map['enabled'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  ToolDefinition copyWith({
    String? name,
    String? description,
    String? prompt,
    DetectionType? detectionType,
    String? detectionPattern,
    ExecutionType? executionType,
    String? websocketUrl,
    String? websocketTrigger,
    String? requestFormat,
    String? responseFormat,
    String? nativeAction,
    bool? enabled,
  }) {
    return ToolDefinition(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      prompt: prompt ?? this.prompt,
      detectionType: detectionType ?? this.detectionType,
      detectionPattern: detectionPattern ?? this.detectionPattern,
      executionType: executionType ?? this.executionType,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      websocketTrigger: websocketTrigger ?? this.websocketTrigger,
      requestFormat: requestFormat ?? this.requestFormat,
      responseFormat: responseFormat ?? this.responseFormat,
      nativeAction: nativeAction ?? this.nativeAction,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }

  bool detectInText(String text) {
    if (!enabled || detectionPattern.isEmpty) return false;

    switch (detectionType) {
      case DetectionType.keyword:
        return text.toLowerCase().contains(detectionPattern.toLowerCase());
      case DetectionType.regex:
        try {
          final regex = RegExp(detectionPattern, caseSensitive: false);
          return regex.hasMatch(text);
        } catch (_) {
          return text.toLowerCase().contains(detectionPattern.toLowerCase());
        }
    }
  }
}
