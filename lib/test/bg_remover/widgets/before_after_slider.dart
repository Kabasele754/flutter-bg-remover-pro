import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class BgRemoverBeforeAfterSlider extends StatefulWidget {
  final Uint8List beforeImage;
  final Uint8List afterImage;
  final int? afterBackgroundColor;
  final Uint8List? afterBackgroundImage;

  const BgRemoverBeforeAfterSlider({
    super.key,
    required this.beforeImage,
    required this.afterImage,
    this.afterBackgroundColor,
    this.afterBackgroundImage,
  });

  @override
  State<BgRemoverBeforeAfterSlider> createState() => _BgRemoverBeforeAfterSliderState();
}

class _BgRemoverBeforeAfterSliderState extends State<BgRemoverBeforeAfterSlider> {
  double _clipPercent = 0.5;
  Size _imageSize = const Size(1, 1);

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(covariant BgRemoverBeforeAfterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beforeImage != widget.beforeImage) {
      _loadImageSize();
    }
  }

  void _loadImageSize() {
    final decoded = img.decodeImage(widget.beforeImage);
    if (decoded != null) {
      setState(() {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildAfterLayer(),
            ClipRect(
              clipper: _SliderClipper(_clipPercent),
              child: _buildBeforeLayer(),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) => _updateClip(details.localPosition.dx, constraints.maxWidth),
                onTapDown: (details) => _updateClip(details.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  painter: _SliderLinePainter(_clipPercent),
                ),
              ),
            ),
            Positioned(top: 12, left: 12, child: _buildLabel('BEFORE')),
            Positioned(top: 12, right: 12, child: _buildLabel('AFTER')),
          ],
        );
      },
    );
  }

  void _updateClip(double dx, double width) {
    setState(() {
      _clipPercent = (dx / width).clamp(0.0, 1.0).toDouble();
    });
  }

  Widget _buildBeforeLayer() {
    return _buildContainedFrame(
      child: Image.memory(
        widget.beforeImage,
        fit: BoxFit.fill,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _buildAfterLayer() {
    return _buildContainedFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.afterBackgroundImage != null)
            Image.memory(widget.afterBackgroundImage!, fit: BoxFit.cover, gaplessPlayback: true)
          else if (widget.afterBackgroundColor != null)
            Container(color: Color(widget.afterBackgroundColor!))
          else
            _buildCheckerboard(),
          Image.memory(widget.afterImage, fit: BoxFit.fill, gaplessPlayback: true),
        ],
      ),
    );
  }

  Widget _buildContainedFrame({required Widget child}) {
    return Container(
      color: const Color(0xFF12121A),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _imageSize.width,
            height: _imageSize.height,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckerboard() {
    return CustomPaint(
      painter: _CheckerPainter(),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SliderClipper extends CustomClipper<Rect> {
  final double percentage;
  _SliderClipper(this.percentage);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width * percentage, size.height);

  @override
  bool shouldReclip(covariant _SliderClipper oldClipper) => oldClipper.percentage != percentage;
}

class _SliderLinePainter extends CustomPainter {
  final double percentage;
  _SliderLinePainter(this.percentage);

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * percentage;
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, size.height / 2), 18, handlePaint);

    final arrowPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = Offset(x, size.height / 2);
    canvas.drawLine(center - const Offset(6, 0), center + const Offset(6, 0), arrowPaint);
    canvas.drawLine(center - const Offset(3, 5), center - const Offset(8, 0), arrowPaint);
    canvas.drawLine(center - const Offset(3, -5), center - const Offset(8, 0), arrowPaint);
    canvas.drawLine(center + const Offset(3, 5), center + const Offset(8, 0), arrowPaint);
    canvas.drawLine(center + const Offset(3, -5), center + const Offset(8, 0), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _SliderLinePainter oldDelegate) => oldDelegate.percentage != percentage;
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 16.0;
    final lightPaint = Paint()..color = const Color(0xFF2A2A35);
    final darkPaint = Paint()..color = const Color(0xFF1F1F28);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isLight = ((x ~/ squareSize) + (y ~/ squareSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isLight ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
