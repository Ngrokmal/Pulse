import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class VoiceWaveformView extends StatefulWidget {
  final List<double> amplitudes;
  final double progress;
  final bool isLive;
  final double height;
  final Color activeColor;
  final Color inactiveColor;
  final Stream<double>? liveAmplitudeStream;

  const VoiceWaveformView({
    super.key,
    this.amplitudes = const [],
    this.progress = 0,
    this.isLive = false,
    this.height = 32,
    this.activeColor = AppColors.primaryAccent,
    this.inactiveColor = Colors.white24,
    this.liveAmplitudeStream,
  });

  @override
  State<VoiceWaveformView> createState() => _VoiceWaveformViewState();
}

class _VoiceWaveformViewState extends State<VoiceWaveformView> with SingleTickerProviderStateMixin {
  static const int _barCount = 28;
  late final AnimationController _controller;
  final Random _random = Random();
  late List<double> _liveBars;
  StreamSubscription<double>? _ampSubscription;

  @override
  void initState() {
    super.initState();
    _liveBars = List.generate(_barCount, (_) => 0.2);
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
      ..addListener(_onTick);
    _bindLiveSource();
  }

  @override
  void didUpdateWidget(covariant VoiceWaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveAmplitudeStream != widget.liveAmplitudeStream || oldWidget.isLive != widget.isLive) {
      _ampSubscription?.cancel();
      _ampSubscription = null;
      _controller.stop();
      _bindLiveSource();
    }
  }

  void _bindLiveSource() {
    if (!widget.isLive) return;
    if (widget.liveAmplitudeStream != null) {
      _ampSubscription = widget.liveAmplitudeStream!.listen((amplitude) {
        if (!mounted) return;
        setState(() {
          _liveBars = [..._liveBars.skip(1), amplitude.clamp(0.05, 1.0)];
        });
      });
    } else {
      _controller.repeat();
    }
  }

  void _onTick() {
    if (!widget.isLive || widget.liveAmplitudeStream != null) return;
    setState(() {
      _liveBars = List.generate(_barCount, (_) => 0.15 + _random.nextDouble() * 0.85);
    });
  }

  @override
  void dispose() {
    _ampSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<double> get _bars {
    if (widget.isLive) return _liveBars;
    if (widget.amplitudes.isNotEmpty) return widget.amplitudes;
    return List.generate(28, (i) => 0.3 + 0.5 * ((i * 37) % 7) / 6);
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeCount = (bars.length * widget.progress).round();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(bars.length, (i) {
              final amplitude = bars[i].clamp(0.1, 1.0);
              final isActive = widget.isLive || i < activeCount;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 3,
                height: widget.height * amplitude,
                decoration: BoxDecoration(
                  color: isActive ? widget.activeColor : widget.inactiveColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
