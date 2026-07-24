import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_duration.dart';

class AnimatedBearWidget extends StatefulWidget {
  final bool isCovered;
  final double lookX;

  const AnimatedBearWidget({super.key, required this.isCovered, required this.lookX});

  @override
  State<AnimatedBearWidget> createState() => _AnimatedBearWidgetState();
}

class _AnimatedBearWidgetState extends State<AnimatedBearWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _pawAnimation;
  Timer? _blinkTimer;
  bool _isBlinking = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: AppDuration.bearCover);
    _pawAnimation = Tween<double>(begin: -60.0, end: 30.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack));
    _startBlinking();
  }

  @override
  void didUpdateWidget(covariant AnimatedBearWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCovered != oldWidget.isCovered) {
      widget.isCovered ? _animationController.forward() : _animationController.reverse();
    }
  }

  void _startBlinking() {
    _blinkTimer = Timer.periodic(AppDuration.blinkInterval, (timer) {
      if (!widget.isCovered && mounted) {
        setState(() => _isBlinking = true);
        Future.delayed(AppDuration.blinkLook, () { if (mounted) setState(() => _isBlinking = false); });
      }
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 130, height: 130,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildEar(isLeft: true), _buildEar(isLeft: false),
            Container(
              decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 3.5)),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: AppDuration.medium, alignment: Alignment(widget.lookX * 0.1, 0.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),
                        if (!widget.isCovered) Row(mainAxisAlignment: MainAxisAlignment.center, children: [_buildEye(), const SizedBox(width: 24), _buildEye()]) else const SizedBox(height: 16),
                        const SizedBox(height: 12), _buildMouth(),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pawAnimation,
                    builder: (_, __) => Positioned(bottom: _pawAnimation.value, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildPaw(), _buildPaw()])),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEar({required bool isLeft}) => Positioned(top: -4, left: isLeft ? 4 : null, right: isLeft ? null : 4, child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)));
  Widget _buildPaw() => Container(width: 38, height: 48, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)));
  Widget _buildEye() => AnimatedContainer(duration: AppDuration.fast, width: 16, height: _isBlinking ? 2 : 16, decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle), child: _isBlinking ? const SizedBox() : Center(child: Transform.translate(offset: Offset(widget.lookX * 0.6, 1.0), child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.eyeIris, shape: BoxShape.circle)))));
  Widget _buildMouth() => Container(width: widget.lookX != 0.0 ? 20 : 24, height: widget.lookX != 0.0 ? 10 : 2, decoration: BoxDecoration(color: widget.lookX != 0.0 ? AppColors.mouthColor : Colors.white54, borderRadius: widget.lookX != 0.0 ? const BorderRadius.vertical(bottom: Radius.circular(10)) : null));
}
