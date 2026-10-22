import 'package:flutter/widgets.dart';

class RuledLinesPainter extends CustomPainter {
  const RuledLinesPainter({
    required this.color,
    required this.spacing,
    required this.offset,
    this.bleed = EdgeInsets.zero,
  });

  final Color color;
  final double spacing;
  final double offset;
  final EdgeInsets bleed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final top = -bleed.top;
    final bottom = size.height + bleed.bottom;
    final left = -bleed.left;
    final right = size.width + bleed.right;
    var y = offset - ((offset - top) / spacing).floor() * spacing;
    while (y <= bottom) {
      canvas.drawRect(Rect.fromLTRB(left, y, right, y + 1), paint);
      y += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant RuledLinesPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.spacing != spacing ||
      oldDelegate.offset != offset ||
      oldDelegate.bleed != bleed;
}
