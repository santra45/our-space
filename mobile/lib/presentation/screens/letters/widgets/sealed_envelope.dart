import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'wax_seal.dart';

class SealedEnvelope extends StatelessWidget {
  const SealedEnvelope({super.key, this.height = 150, this.breathe = true});

  final double height;
  final bool breathe;

  @override
  Widget build(BuildContext context) {
    const seal = WaxSeal();
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 14, 26, 0),
        child: Transform.rotate(
          angle: -3 * math.pi / 180,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment(-0.34, -0.94),
                end: Alignment(0.34, 0.94),
                colors: [LetterInk.envelopeLight, LetterInk.envelopeDeep],
              ),
              boxShadow: const [BoxShadow(color: LetterInk.envelopeShadow, offset: Offset(0, 18), blurRadius: 25)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      widthFactor: 1,
                      heightFactor: 0.6,
                      child: CustomPaint(painter: EnvelopeFlapPainter()),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.1),
                    child: breathe ? const BreathingSeal(child: seal) : seal,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EnvelopeFlapPainter extends CustomPainter {
  const EnvelopeFlapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height * 74 / 80)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = LetterInk.envelopeFlap);
    canvas.drawPath(
      path,
      Paint()
        ..color = LetterInk.envelopeEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant EnvelopeFlapPainter oldDelegate) => false;
}
