import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/tool_definition.dart';

class ToolService {
  List<ToolDefinition> _tools = [];
  final StreamController<ToolCallEvent> _eventController =
      StreamController<ToolCallEvent>.broadcast();

  Stream<ToolCallEvent> get events => _eventController.stream;
  List<ToolDefinition> get tools => List.unmodifiable(_tools);

  List<ToolDefinition> get enabledTools =>
      _tools.where((t) => t.enabled).toList();

  void setTools(List<ToolDefinition> tools) {
    _tools = tools;
  }

  ToolCallResult? detectToolCall(String response) {
    for (final tool in enabledTools) {
      if (tool.detectInText(response)) {
        return ToolCallResult(
          tool: tool,
          detectedText: _extractDetectedText(response, tool),
          rawResponse: response,
        );
      }
    }
    return null;
  }

  String _extractDetectedText(String response, ToolDefinition tool) {
    switch (tool.detectionType) {
      case DetectionType.keyword:
        final idx = response.toLowerCase().indexOf(tool.detectionPattern.toLowerCase());
        if (idx < 0) return tool.detectionPattern;
        final start = idx > 20 ? idx - 20 : 0;
        final end = idx + tool.detectionPattern.length + 20;
        return response.substring(start, end.clamp(0, response.length));
      case DetectionType.regex:
        try {
          final regex = RegExp(tool.detectionPattern, caseSensitive: false);
          final match = regex.firstMatch(response);
          return match?.group(0) ?? tool.detectionPattern;
        } catch (_) {
          return tool.detectionPattern;
        }
    }
  }

  Future<ToolExecutionResult> executeTool(ToolCallResult call) async {
    final tool = call.tool;
    _eventController.add(ToolCallEvent(
      toolId: tool.id,
      status: ToolCallStatus.executing,
    ));

    try {
      switch (tool.executionType) {
        case ExecutionType.websocket:
          return await _executeWebsocket(tool, call);
        case ExecutionType.native:
          return await _executeNative(tool, call);
      }
    } catch (e) {
      _eventController.add(ToolCallEvent(
        toolId: tool.id,
        status: ToolCallStatus.failed,
        error: e.toString(),
      ));
      return ToolExecutionResult(
        success: false,
        error: e.toString(),
        tool: tool,
      );
    }
  }

  Future<ToolExecutionResult> _executeWebsocket(
    ToolDefinition tool,
    ToolCallResult call,
  ) async {
    if (tool.websocketUrl.isEmpty) {
      return ToolExecutionResult(
        success: false,
        error: 'No WebSocket URL configured',
        tool: tool,
      );
    }

    try {
      final uri = Uri.parse(tool.websocketUrl);
      final channel = WebSocketChannel.connect(uri);

      final requestPayload = tool.requestFormat
          .replaceAll('{trigger}', tool.websocketTrigger)
          .replaceAll('{content}', call.detectedText)
          .replaceAll('{response}', call.rawResponse);

      final completer = Completer<ToolExecutionResult>();
      String responseData = '';

      final sub = channel.stream.listen(
        (data) {
          responseData += data.toString();
          if (!completer.isCompleted) {
            try {
              final response = jsonDecode(responseData);
              completer.complete(ToolExecutionResult(
                success: true,
                data: response,
                tool: tool,
              ));
            } catch (_) {
              completer.complete(ToolExecutionResult(
                success: true,
                data: {'raw': responseData},
                tool: tool,
              ));
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.complete(ToolExecutionResult(
              success: false,
              error: e.toString(),
              tool: tool,
            ));
          }
        },
      );

      channel.sink.add(requestPayload);

      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          channel.sink.close();
          return ToolExecutionResult(
            success: false,
            error: 'WebSocket timeout',
            tool: tool,
          );
        },
      );

      await sub.cancel();
      await channel.sink.close();

      _eventController.add(ToolCallEvent(
        toolId: tool.id,
        status: result.success ? ToolCallStatus.success : ToolCallStatus.failed,
      ));

      return result;
    } catch (e) {
      return ToolExecutionResult(
        success: false,
        error: e.toString(),
        tool: tool,
      );
    }
  }

  Future<ToolExecutionResult> _executeNative(
    ToolDefinition tool,
    ToolCallResult call,
  ) async {
    _eventController.add(ToolCallEvent(
      toolId: tool.id,
      status: ToolCallStatus.success,
    ));

    return ToolExecutionResult(
      success: true,
      data: {
        'action': tool.nativeAction,
        'tool': tool.name,
        'matched': call.detectedText,
      },
      tool: tool,
    );
  }

  void dispose() {
    _eventController.close();
  }
}

class ToolCallEvent {
  final String toolId;
  final ToolCallStatus status;
  final String? error;

  ToolCallEvent({
    required this.toolId,
    required this.status,
    this.error,
  });
}

class ToolCallResult {
  final ToolDefinition tool;
  final String detectedText;
  final String rawResponse;

  ToolCallResult({
    required this.tool,
    required this.detectedText,
    required this.rawResponse,
  });
}

class ToolExecutionResult {
  final bool success;
  final dynamic data;
  final String? error;
  final ToolDefinition tool;

  ToolExecutionResult({
    required this.success,
    this.data,
    this.error,
    required this.tool,
  });
}
