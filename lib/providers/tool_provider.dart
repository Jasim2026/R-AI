import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/tool_definition.dart';
import '../services/tool_service.dart';
import '../services/cache_service.dart';

class ToolProvider extends ChangeNotifier {
  final ToolService _toolService;
  final CacheService _cacheService;

  List<ToolDefinition> _tools = [];
  ToolCallStatus _lastStatus = ToolCallStatus.idle;
  String? _lastError;
  ToolDefinition? _lastDetectedTool;

  ToolProvider({
    required ToolService toolService,
    required CacheService cacheService,
  })  : _toolService = toolService,
        _cacheService = cacheService;

  List<ToolDefinition> get tools => _tools;
  List<ToolDefinition> get enabledTools => _tools.where((t) => t.enabled).toList();
  bool get toolCallingEnabled => _cacheService.toolCallingEnabled;
  ToolCallStatus get lastStatus => _lastStatus;
  String? get lastError => _lastError;
  ToolDefinition? get lastDetectedTool => _lastDetectedTool;

  Future<void> loadTools() async {
    final json = _cacheService.toolsJson;
    if (json != null && json.isNotEmpty) {
      try {
        final list = (jsonDecode(json) as List)
            .map((t) => ToolDefinition.fromMap(t as Map<String, dynamic>))
            .toList();
        _tools = list;
        _toolService.setTools(_tools);
      } catch (_) {
        _tools = [];
      }
    }
    notifyListeners();

    _toolService.events.listen((event) {
      _lastStatus = event.status;
      if (event.error != null) {
        _lastError = event.error;
      }
      notifyListeners();
    });
  }

  Future<void> _saveTools() async {
    final json = jsonEncode(_tools.map((t) => t.toMap()).toList());
    await _cacheService.setToolsJson(json);
    _toolService.setTools(_tools);
  }

  void setToolCallingEnabled(bool value) {
    _cacheService.toolCallingEnabled = value;
    notifyListeners();
  }

  ToolCallResult? detectToolCall(String response) {
    if (!toolCallingEnabled) return null;
    final result = _toolService.detectToolCall(response);
    if (result != null) {
      _lastDetectedTool = result.tool;
      _lastStatus = ToolCallStatus.detected;
      notifyListeners();
    }
    return result;
  }

  Future<ToolExecutionResult> executeTool(ToolCallResult call) async {
    final result = await _toolService.executeTool(call);
    notifyListeners();
    return result;
  }

  Future<void> addTool(ToolDefinition tool) async {
    _tools.add(tool);
    await _saveTools();
    notifyListeners();
  }

  Future<void> updateTool(ToolDefinition tool) async {
    final idx = _tools.indexWhere((t) => t.id == tool.id);
    if (idx >= 0) {
      _tools[idx] = tool;
      await _saveTools();
      notifyListeners();
    }
  }

  Future<void> removeTool(String id) async {
    _tools.removeWhere((t) => t.id == id);
    await _saveTools();
    notifyListeners();
  }

  Future<void> toggleTool(String id) async {
    final idx = _tools.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _tools[idx] = _tools[idx].copyWith(enabled: !_tools[idx].enabled);
      await _saveTools();
      notifyListeners();
    }
  }

  void clearLastDetection() {
    _lastDetectedTool = null;
    _lastStatus = ToolCallStatus.idle;
    _lastError = null;
    notifyListeners();
  }
}
