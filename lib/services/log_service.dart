import 'dart:io';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const String _logDirPath = '/storage/emulated/0/R-Ai';
  static const String _logFileName = 'log.txt';
  late final File _logFile;

  bool _initialized = false;
  final List<Future<void> Function()> _queue = [];
  bool _processing = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final dir = Directory(_logDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _logFile = File('$_logDirPath/$_logFileName');
      // Clear old log on startup
      await _logFile.writeAsString('');
      _initialized = true;
    } catch (e) {
      print('Failed to initialize LogService: $e');
    }
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> log(String tag, String message, {String? error, StackTrace? stackTrace}) async {
    if (!_initialized) await initialize();
    if (!_initialized) return;

    final timestamp = _formatTimestamp();
    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] $tag: $message');
    if (error != null) {
      buffer.writeln('  ERROR: $error');
    }
    if (stackTrace != null) {
      buffer.writeln('  STACK: $stackTrace');
    }

    await _enqueueWrite(buffer.toString());
  }

  Future<void> logError(String tag, String message, dynamic error, StackTrace? stackTrace) async {
    await log(tag, message, error: error.toString(), stackTrace: stackTrace);
  }

  Future<void> _enqueueWrite(String text) async {
    _queue.add(() async {
      try {
        await _logFile.writeAsString('$text', mode: FileMode.append);
      } catch (e) {
        print('Failed to write log: $e');
      }
    });
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      try {
        await task();
      } catch (e) {
        print('Log queue error: $e');
      }
    }

    _processing = false;
  }

  Future<void> clear() async {
    if (!_initialized) return;

    try {
      await _logFile.writeAsString('');
    } catch (e) {
      print('Failed to clear log: $e');
    }
  }

  Future<String> readLog() async {
    if (!_initialized) return '';

    try {
      return await _logFile.readAsString();
    } catch (e) {
      return 'Failed to read log: $e';
    }
  }
}
