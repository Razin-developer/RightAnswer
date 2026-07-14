import 'package:flutter/material.dart';

/// Premium brand mark for RightAnswer.
///
/// A curved checkmark with a punctuation dot at the tip — represents
/// the moment of a correct answer, elegant and minimal.
class AppLogo extends StatelessWidget {
  final double size;

  /// Override background color. Defaults to [ColorScheme.primary].
  final Color? backgroundColor;

  /// Override icon color. Defaults to white.
  final Color iconColor;

  const AppLogo({
    super.key,
    this.size = 32,
    this.backgroundColor,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final radius = size * 0.225;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(
        painter: _MarkPainter(color: iconColor),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  const _MarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.093
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Left stroke — short, slightly angled
    final path = Path();
    path.moveTo(w * 0.188, h * 0.525);
    path.lineTo(w * 0.375, h * 0.725);

    // Right stroke — curves gracefully upward via quadratic bezier
    path.quadraticBezierTo(
      w * 0.625, h * 0.575, // control point (pulls the curve inward)
      w * 0.825, h * 0.250, // end point (top-right)
    );

    canvas.drawPath(path, strokePaint);

    // Dot accent at the tip — the punctuation that makes the mark unique
    canvas.drawCircle(
      Offset(w * 0.825, h * 0.250),
      w * 0.058,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
