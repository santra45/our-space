import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrCode, QrErrorCorrectLevel, QrImage;

import '../../theme/app_colors.dart';

@immutable
class InviteQrMatrix {
  const InviteQrMatrix._(this.moduleCount, this._dark);

  static InviteQrMatrix? encode(String data) {
    if (data.isEmpty) return null;
    try {
      final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
      final image = QrImage(code);
      final count = image.moduleCount;
      final dark = List<bool>.generate(count * count, (i) => image.isDark(i ~/ count, i % count));
      return InviteQrMatrix._(count, dark);
    } catch (_) {
      return null;
    }
  }

  final int moduleCount;
  final List<bool> _dark;

  bool isDark(int row, int col) => _dark[row * moduleCount + col];

  int get darkModules => _dark.where((d) => d).length;
}

@immutable
class InviteQrLayout {
  const InviteQrLayout({required this.moduleCount, this.size = InviteQr.webSize, this.margin = InviteQr.webMargin});

  final int moduleCount;
  final double size;
  final int margin;

  int get modulesAcross => moduleCount + margin * 2;

  double get moduleSize => size / modulesAcross;

  double get quietZone => moduleSize * margin;

  Rect moduleRect(int row, int col) =>
      Rect.fromLTWH((col + margin) * moduleSize, (row + margin) * moduleSize, moduleSize, moduleSize);
}

class InviteQr extends StatefulWidget {
  const InviteQr({
    super.key,
    required this.data,
    this.size = webSize,
    this.margin = webMargin,
    this.dark = AppColors.slate800,
    this.light = AppColors.white,
  });

  static const double webSize = 190;
  static const int webMargin = 2;

  final String data;
  final double size;
  final int margin;
  final Color dark;
  final Color light;

  @override
  State<InviteQr> createState() => _InviteQrState();
}

class _InviteQrState extends State<InviteQr> {
  late InviteQrMatrix? _matrix = InviteQrMatrix.encode(widget.data);

  @override
  void didUpdateWidget(covariant InviteQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _matrix = InviteQrMatrix.encode(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;
    return SizedBox.square(
      dimension: widget.size,
      child: matrix == null
          ? ColoredBox(color: widget.light)
          : CustomPaint(
              painter: InviteQrPainter(
                matrix: matrix,
                layout: InviteQrLayout(moduleCount: matrix.moduleCount, size: widget.size, margin: widget.margin),
                dark: widget.dark,
                light: widget.light,
              ),
            ),
    );
  }
}

class InviteQrPainter extends CustomPainter {
  const InviteQrPainter({required this.matrix, required this.layout, required this.dark, required this.light});

  final InviteQrMatrix matrix;
  final InviteQrLayout layout;
  final Color dark;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final path = Path();
    for (var row = 0; row < matrix.moduleCount; row++) {
      for (var col = 0; col < matrix.moduleCount; col++) {
        if (matrix.isDark(row, col)) path.addRect(layout.moduleRect(row, col));
      }
    }
    canvas.drawPath(path, Paint()..color = dark);
  }

  @override
  bool shouldRepaint(InviteQrPainter oldDelegate) {
    return !identical(oldDelegate.matrix, matrix) ||
        oldDelegate.layout.size != layout.size ||
        oldDelegate.layout.margin != layout.margin ||
        oldDelegate.dark != dark ||
        oldDelegate.light != light;
  }
}
