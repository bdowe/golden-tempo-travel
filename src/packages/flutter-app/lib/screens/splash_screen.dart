import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/brand_logo.dart';

/// Branded boot splash shown while the stored session is being restored.
///
/// Pixel-matched to the static HTML splash in web/index.html — same gradient,
/// badge geometry (120×120: 72px mark + 24px padding, radius 20), pulse
/// (1.0→1.04 over 1.8s), and spinner position (center 96px below viewport
/// center) — so the web handoff reads as one continuous screen. If you change
/// dimensions here, change index.html too.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.brandGradient),
      // Two independent Centers (not a Column) so the badge sits at the exact
      // viewport center, matching the CSS `top:50%/left:50%` layer.
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.04).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: BrandBadge(
                padding: const EdgeInsets.all(AppSpacing.xl),
                borderRadius: AppRadius.lgAll,
                // BrandLogo.mark only sets height; the SizedBox keeps the badge
                // 120px wide even if the PNG isn't perfectly square.
                child: const SizedBox.square(
                  dimension: 72,
                  child: BrandLogo.mark(size: 72),
                ),
              ),
            ),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, 96),
              child: const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
