import 'dart:math';
import 'package:flutter/material.dart';
import '../services/ram_monitor_service.dart';
import '../utils/theme.dart';

class RamUsageIndicator extends StatefulWidget {
  final RamMonitorService monitor;

  const RamUsageIndicator({super.key, required this.monitor});

  @override
  State<RamUsageIndicator> createState() => _RamUsageIndicatorState();
}

class _RamUsageIndicatorState extends State<RamUsageIndicator> {
  RamInfo? _info;

  @override
  void initState() {
    super.initState();
    _info = widget.monitor.lastInfo;
    widget.monitor.stream.listen((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = _info?.percentage ?? 0;
    final used = _info?.usedGb ?? 0;
    final total = _info?.totalGb ?? 0;

    final color = pct > 85
        ? AppColors.error
        : pct > 65
            ? AppColors.warning
            : AppColors.success;

    return GestureDetector(
      onTap: () => _showRamDetail(),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CustomPaint(
                painter: _CircularProgressPainter(
                  progress: pct / 100,
                  color: color,
                  backgroundColor: AppColors.surfaceLight,
                  strokeWidth: 3,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${pct.round()}',
                  style: AppColors.font(
                    size: 9,
                    weight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  '%',
                  style: AppColors.font(
                    size: 6,
                    color: color.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRamDetail() {
    final used = _info?.usedGb ?? 0;
    final total = _info?.totalGb ?? 0;
    final pct = _info?.percentage ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'RAM Usage',
              style: AppColors.font(
                color: AppColors.textPrimary,
                size: 18,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: CustomPaint(
                      painter: _CircularProgressPainter(
                        progress: pct / 100,
                        color: pct > 85
                            ? AppColors.error
                            : pct > 65
                                ? AppColors.warning
                                : AppColors.success,
                        backgroundColor: AppColors.surfaceLight,
                        strokeWidth: 8,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${pct.round()}',
                        style: AppColors.font(
                          size: 28,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '%',
                        style: AppColors.font(
                          size: 14,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${used.toStringAsFixed(1)} GB / ${total.toStringAsFixed(1)} GB',
              style: AppColors.font(
                color: AppColors.textSecondary,
                size: 14,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
