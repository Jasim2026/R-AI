import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/chat_session.dart';
import '../models/llm_model.dart';

class StorageService {
  static StorageService? _instance;
  late final Directory _appDir;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    _appDir = await getApplicationDocumentsDirectory();
  }

  String get appPath => _appDir.path;

  Future<void> saveChatSession(ChatSession session) async {
    final file = File('${_appDir.path}/${session.id}.json');
    await file.writeAsString(jsonEncode(session.toMap()));
  }

  Future<List<ChatSession>> loadAllChatSessions() async {
    final files = _appDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final sessions = <ChatSession>[];
    for (final file in files) {
      try {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        sessions.add(ChatSession.fromMap(map));
      } catch (_) {}
    }

    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  Future<void> deleteChatSession(String sessionId) async {
    final file = File('${_appDir.path}/$sessionId.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> saveModels(List<LLMModel> models) async {
    final file = File('${_appDir.path}/models.json');
    final json = models.map((m) => m.toMap()).toList();
    await file.writeAsString(jsonEncode(json));
  }

  Future<List<LLMModel>> loadModels() async {
    final file = File('${_appDir.path}/models.json');
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as List;
      return json.map((m) => LLMModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteModelFile(String modelPath) async {
    final file = File(modelPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
