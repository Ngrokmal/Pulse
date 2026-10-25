import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/photo_flow_result.dart';
import '../widgets/photo_placeholder.dart';
import 'image_preview_screen.dart';

class ImageCropScreen extends StatefulWidget {
  final bool isCircle;
  final File sourceFile;

  const ImageCropScreen({super.key, required this.isCircle, required this.sourceFile});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _boundaryKey = GlobalKey();
  double _rotationQuarterTurns = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _controller.value = Matrix4.identity();
      _rotationQuarterTurns = 0;
    });
  }

  void _rotate90() {
    setState(() => _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4);
  }

  Rect _frameRect(Size size) {
    return widget.isCircle
        ? Rect.fromCircle(center: size.center(Offset.zero), radius: math.min(size.width, size.height) * 0.34)
        : Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.9, height: size.width * 0.9 * 9 / 16);
  }

  Future<File?> _captureCroppedFile() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image fullImage = await boundary.toImage(pixelRatio: 2.0);
    final Size logicalSize = boundary.size;
    final double scale = fullImage.width / logicalSize.width;
    final Rect frame = _frameRect(logicalSize);
    final Rect scaledFrame = Rect.fromLTWH(
      frame.left * scale,
      frame.top * scale,
      frame.width * scale,
      frame.height * scale,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outputRect = Rect.fromLTWH(0, 0, scaledFrame.width, scaledFrame.height);

    if (widget.isCircle) {
      canvas.clipPath(Path()..addOval(outputRect));
    } else {
      canvas.clipRRect(RRect.fromRectAndRadius(outputRect, const Radius.circular(12)));
    }
    canvas.drawImageRect(fullImage, scaledFrame, outputRect, Paint());

    final ui.Image cropped = await recorder.endRecording().toImage(
          outputRect.width.round().clamp(1, 4096),
          outputRect.height.round().clamp(1, 4096),
        );
    final ByteData? pngBytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) return null;

    final tempDir = await Directory.systemTemp.createTemp('pulse_profile_photo');
    final outFile = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png');
    await outFile.writeAsBytes(pngBytes.buffer.asUint8List());
    return outFile;
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final croppedFile = await _captureCroppedFile();
    if (!mounted) return;

    if (croppedFile == null) {
      setState(() => _busy = false);
      return;
    }

    final result = await Navigator.of(context).push<PhotoFlowResult>(
      MaterialPageRoute(builder: (_) => ImagePreviewScreen(isCircle: widget.isCircle, imageFile: croppedFile)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return;
    if (result.cancelled) {
      Navigator.of(context).pop(const PhotoFlowResult.cancelled());
    } else if (result.file != null) {
      Navigator.of(context).pop(PhotoFlowResult.confirmed(result.file!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: widget.isCircle ? 'Move & Scale' : 'Crop Cover Photo',
              onCancel: () => Navigator.of(context).pop(const PhotoFlowResult.cancelled()),
              onDone: _busy ? null : _done,
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    const ColoredBox(color: Colors.black),
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: InteractiveViewer(
                        transformationController: _controller,
                        minScale: 0.6,
                        maxScale: 4.0,
                        boundaryMargin: const EdgeInsets.all(200),
                        child: Center(
                          child: AnimatedRotation(
                            turns: _rotationQuarterTurns / 4,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            child: SizedBox(
                              width: 340,
                              height: 340,
                              child: PhotoPlaceholder(icon: Icons.photo_rounded, iconSize: 64, imageFile: widget.sourceFile),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _CropMaskPainter(isCircle: widget.isCircle),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomToolbar(onRotate: _rotate90, onReset: _reset),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onCancel;
  final VoidCallback? onDone;

  const _TopBar({required this.title, required this.onCancel, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.small, vertical: AppSpacing.small),
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text('Cancel', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: onDone,
            child: onDone == null
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Done', style: AppTypography.body.copyWith(color: AppColors.primaryAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _BottomToolbar extends StatelessWidget {
  final VoidCallback onRotate;
  final VoidCallback onReset;

  const _BottomToolbar({required this.onRotate, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.medium),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolButton(icon: Icons.rotate_90_degrees_ccw_rounded, label: 'Rotate', onTap: onRotate),
          const SizedBox(width: AppSpacing.large),
          _ToolButton(icon: Icons.restart_alt_rounded, label: 'Reset', onTap: onReset),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.small),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white12,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(label, style: AppTypography.caption.copyWith(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  final bool isCircle;
  const _CropMaskPainter({required this.isCircle});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frameRect = isCircle
        ? Rect.fromCircle(center: size.center(Offset.zero), radius: math.min(size.width, size.height) * 0.34)
        : Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.9, height: size.width * 0.9 * 9 / 16);

    final Path holePath = isCircle
        ? (Path()..addOval(frameRect))
        : (Path()..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(12))));

    final Path fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path maskPath = Path.combine(PathOperation.difference, fullPath, holePath);

    canvas.drawPath(maskPath, Paint()..color = Colors.black.withOpacity(0.65));
    canvas.drawPath(
      holePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) => oldDelegate.isCircle != isCircle;
}
