import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_art.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_state.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';

const String drawables = 'android/app/src/main/res/drawable-nodpi';

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Uint8List> preview(SkyWidgetImages images) async {
  final sky = await decode(images.sky);
  final stars = await decode(images.stars!);
  final side = sky.width.toDouble();
  final unit = side / 150;
  final room = Rect.fromLTRB(6 * unit, 6 * unit, side - 6 * unit, side - 30 * unit);
  final box = Rect.fromCenter(center: room.center, width: room.shortestSide, height: room.shortestSide);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..filterQuality = FilterQuality.high;
  canvas.drawImage(sky, Offset.zero, paint);
  canvas.drawImageRect(stars, Offset.zero & Size(stars.width.toDouble(), stars.height.toDouble()), box, paint);
  final image = await recorder.endRecording().toImage(sky.width, sky.height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('draws the pictures the Android widget starts with', (tester) async {
    await tester.runAsync(() async {
      const art = SkyWidgetArt();
      final empty = await art.render(const SkyWidgetState.empty());
      File('$drawables/sky_widget_empty.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(empty.sky);
      final series = ConstellationSeries.fromDays([
        for (var day = 1; day <= 29; day++) '2026-01-${day.toString().padLeft(2, '0')}',
      ], today: '2026-01-29');
      final sample = await art.render(SkyWidgetState.forSeries(series, night: true));
      File('$drawables/sky_widget_preview.png').writeAsBytesSync(await preview(sample));
    });
  });
}
