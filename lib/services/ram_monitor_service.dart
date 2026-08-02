import 'dart:async';
import 'dart:io';

class RamInfo {
  final double totalGb;
  final double usedGb;
  final double percentage;

  RamInfo({
    required this.totalGb,
    required this.usedGb,
    required this.percentage,
  });
}

class RamMonitorService {
  Timer? _timer;
  final StreamController<RamInfo> _controller =
      StreamController<RamInfo>.broadcast();

  Stream<RamInfo> get stream => _controller.stream;
  RamInfo? _lastInfo;
  RamInfo? get lastInfo => _lastInfo;

  void startMonitoring({Duration interval = const Duration(seconds: 3)}) {
    _timer?.cancel();
    _readRamInfo();
    _timer = Timer.periodic(interval, (_) => _readRamInfo());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _readRamInfo() async {
    try {
      final info = await _parseMemInfo();
      if (info != null) {
        _lastInfo = info;
        _controller.add(info);
      }
    } catch (_) {}
  }

  Future<RamInfo?> _parseMemInfo() async {
    try {
      final file = File('/proc/meminfo');
      if (!await file.exists()) return _getFallbackInfo();

      final content = await file.readAsString();
      int? totalKb;
      int? availableKb;

      for (final line in content.split('\n')) {
        if (line.startsWith('MemTotal:')) {
          totalKb = int.tryParse(
            line.replaceAll(RegExp(r'[^0-9]'), ''),
          );
        } else if (line.startsWith('MemAvailable:')) {
          availableKb = int.tryParse(
            line.replaceAll(RegExp(r'[^0-9]'), ''),
          );
        }
        if (totalKb != null && availableKb != null) break;
      }

      if (totalKb != null && availableKb != null) {
        final totalGb = totalKb / (1024 * 1024);
        final usedGb = (totalKb - availableKb) / (1024 * 1024);
        final pct = totalKb > 0 ? ((totalKb - availableKb) / totalKb) * 100 : 0.0;
        return RamInfo(
          totalGb: totalGb,
          usedGb: usedGb,
          percentage: pct,
        );
      }

      return _getFallbackInfo();
    } catch (_) {
      return _getFallbackInfo();
    }
  }

  RamInfo _getFallbackInfo() {
    return RamInfo(totalGb: 0, usedGb: 0, percentage: 0);
  }

  void dispose() {
    stopMonitoring();
    _controller.close();
  }
}
