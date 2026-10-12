import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sync/invite_qr.dart';
import 'package:our_space_mobile/presentation/screens/sync/qr_scanner.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';

const String sampleLink =
    'https://sameskytonight.vercel.app/#connect=love-abcdefghjkmnpqrs&salt=AAECAwQFBgcICQoLDA0ODw&start=2021-06-14&names=Sam+%26+Alex';

class ByteDataReader {
  ByteDataReader(this.width, this.bytes);

  final int width;
  final List<int> bytes;

  Color colorAt(int x, int y) {
    final i = (y * width + x) * 4;
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  }
}

void main() {
  test('encodes the invite at the web error correction level with a full matrix', () {
    expect(InviteQrMatrix.encode(''), isNull);
    final matrix = InviteQrMatrix.encode(sampleLink)!;
    expect((matrix.moduleCount - 17) % 4, 0);
    expect(matrix.moduleCount, greaterThanOrEqualTo(21));
    for (var i = 0; i < 7; i++) {
      expect(matrix.isDark(0, i), isTrue);
      expect(matrix.isDark(i, 0), isTrue);
      expect(matrix.isDark(6, i), isTrue);
    }
    expect(matrix.isDark(1, 1), isFalse);
    expect(matrix.isDark(3, 3), isTrue);
    expect(matrix.darkModules, greaterThan(0));
  });

  test('keeps the web two-module quiet zone inside 190 pixels', () {
    const layout = InviteQrLayout(moduleCount: 33);
    expect(layout.size, 190);
    expect(layout.margin, 2);
    expect(layout.modulesAcross, 37);
    expect(layout.moduleSize, closeTo(190 / 37, 1e-9));
    expect(layout.quietZone, closeTo(2 * 190 / 37, 1e-9));
    expect(layout.moduleRect(0, 0).left, closeTo(layout.quietZone, 1e-9));
    expect(layout.moduleRect(32, 32).right, closeTo(190 - layout.quietZone, 1e-9));
  });

  testWidgets('paints white around the code and slate modules inside it', (tester) async {
    final matrix = InviteQrMatrix.encode(sampleLink)!;
    final layout = InviteQrLayout(moduleCount: matrix.moduleCount);
    final painter = InviteQrPainter(matrix: matrix, layout: layout, dark: AppColors.slate800, light: AppColors.white);
    final reader = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size.square(190));
      final image = await recorder.endRecording().toImage(190, 190);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return ByteDataReader(190, data!.buffer.asUint8List());
    });
    final m = layout.moduleSize;
    expect(reader!.colorAt((m * 0.5).floor(), (m * 0.5).floor()), AppColors.white);
    expect(reader.colorAt((m * 1.5).floor(), (m * 1.5).floor()), AppColors.white);
    expect(reader.colorAt((m * 2.5).floor(), (m * 2.5).floor()), AppColors.slate800);
    expect(reader.colorAt((m * 3.5).floor(), (m * 3.5).floor()), AppColors.white);
    expect(reader.colorAt((m * 5.5).floor(), (m * 5.5).floor()), AppColors.slate800);
    expect(reader.colorAt(189, 189), AppColors.white);
    expect(painter.shouldRepaint(painter), isFalse);
  });

  testWidgets('the QR widget is the web size and re-encodes when the link changes', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: InviteQr(data: sampleLink)),
    ));
    expect(tester.getSize(find.byType(InviteQr)), const Size.square(190));
    final first = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(InviteQr), matching: find.byType(CustomPaint)),
    );
    final firstMatrix = (first.painter! as InviteQrPainter).matrix;

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: InviteQr(data: '$sampleLink&x=1')),
    ));
    final second = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(InviteQr), matching: find.byType(CustomPaint)),
    );
    expect(identical((second.painter! as InviteQrPainter).matrix, firstMatrix), isFalse);
  });

  test('the scanner only hands back payloads that read as an invite, like the web', () {
    expect(acceptScannedInvite(null), isNull);
    expect(acceptScannedInvite('   '), isNull);
    expect(acceptScannedInvite('not a pairing code!'), isNull);
    expect(acceptScannedInvite('  $sampleLink  '), sampleLink);
    expect(acceptScannedInvite('love-abcdefgh'), 'love-abcdefgh');
    expect(parseInvite(acceptScannedInvite(sampleLink))!.partnerPeerId, 'love-abcdefghjkmnpqrs');
  });
}
