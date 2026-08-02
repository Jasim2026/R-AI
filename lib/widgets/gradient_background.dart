import 'package:flutter/material.dart';
import '../utils/theme.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;
  final bool showOrbs;

  const GradientBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.background,
            Color(0xFF0D0D15),
            AppColors.background,
          ],
        ),
      ),
      child: Stack(
        children: [
          if (showOrbs) ...[
            Positioned(
              top: -100,
              right: -80,
              child: _buildOrb(
                AppColors.primary.withOpacity(0.08),
                200,
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: _buildOrb(
                AppColors.accent.withOpacity(0.06),
                160,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: -40,
              child: _buildOrb(
                AppColors.primary.withOpacity(0.04),
                120,
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}