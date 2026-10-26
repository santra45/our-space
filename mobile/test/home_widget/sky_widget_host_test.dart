import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_art.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_host.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_state.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';

class RecordingHost extends SkyWidgetHost {
  final List<String> calls = [];
  final Map<String, Object?> saved = {};
  final Map<String, Uint8List> images = {};
  int updates = 0;

  @override
  Future<void> saveImage(String key, Uint8List png) async {
    calls.add('image $key');
    images[key] = png;
    saved[key] = '/files/home_widget/$key.png';
  }

  @override
  Future<void> save(String key, Object? value) async {
    calls.add('save $key');
    if (value == null) {
      saved.remove(key);
      images.remove(key);
    } else {
      saved[key] = value;
    }
  }

  @override
  Future<void> update() async {
    calls.add('update');
    updates++;
  }
}

class StubArt extends SkyWidgetArt {
  const StubArt();

  static final Uint8List sky = Uint8List.fromList([1, 2, 3]);
  static final Uint8List stars = Uint8List.fromList([4, 5, 6]);

  @override
  Future<SkyWidgetImages> render(SkyWidgetState state) async =>
      SkyWidgetImages(sky: sky, stars: state.isEmpty ? null : stars);
}

ConstellationSeries seriesOf(int stars) {
  final days = [for (var i = 0; i < stars; i++) DateTime.utc(2026, 1, 1 + i).toIso8601String().substring(0, 10)];
  return ConstellationSeries.fromDays(days, today: days.last);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('publishing to the widget', () {
    test('a sky with stars sends both pictures, the label and the time of day, then refreshes', () async {
      final host = RecordingHost();
      await SkyWidgetPublisher(
        host: host,
        art: const StubArt(),
      ).publish(SkyWidgetState.forSeries(seriesOf(4), night: false));
      expect(host.calls, [
        'image ${SkyWidgetKeys.sky}',
        'image ${SkyWidgetKeys.stars}',
        'save ${SkyWidgetKeys.label}',
        'save ${SkyWidgetKeys.night}',
        'update',
      ]);
      expect(host.saved, {
        SkyWidgetKeys.sky: '/files/home_widget/${SkyWidgetKeys.sky}.png',
        SkyWidgetKeys.stars: '/files/home_widget/${SkyWidgetKeys.stars}.png',
        SkyWidgetKeys.label: '4 stars',
        SkyWidgetKeys.night: false,
      });
      expect(host.images[SkyWidgetKeys.sky], StubArt.sky);
      expect(host.images[SkyWidgetKeys.stars], StubArt.stars);
    });

    test('an empty sky clears the old stars and says Our Space', () async {
      final host = RecordingHost();
      final publisher = SkyWidgetPublisher(host: host, art: const StubArt());
      await publisher.publish(SkyWidgetState.forSeries(seriesOf(9), night: true));
      host.calls.clear();
      await publisher.publish(const SkyWidgetState.empty());
      expect(host.calls, [
        'image ${SkyWidgetKeys.sky}',
        'save ${SkyWidgetKeys.stars}',
        'save ${SkyWidgetKeys.label}',
        'save ${SkyWidgetKeys.night}',
        'update',
      ]);
      expect(host.saved.containsKey(SkyWidgetKeys.stars), isFalse);
      expect(host.images.containsKey(SkyWidgetKeys.stars), isFalse);
      expect(host.saved[SkyWidgetKeys.label], 'Our Space');
      expect(host.saved[SkyWidgetKeys.night], isTrue);
      expect(host.updates, 2);
    });

    test('only the widget keys are ever written', () async {
      final host = RecordingHost();
      final publisher = SkyWidgetPublisher(host: host, art: const StubArt());
      await publisher.publish(SkyWidgetState.forSeries(seriesOf(30), night: true));
      await publisher.publish(const SkyWidgetState.empty(night: false));
      final keys = {
        for (final call in host.calls)
          if (call != 'update') call.split(' ').last,
      };
      expect(SkyWidgetKeys.all.toSet().containsAll(keys), isTrue);
    });

    test('the widget only exists on Android phones', () {
      expect(SkyWidgetPublisher.forPlatform(), Platform.isAndroid ? isNotNull : isNull);
    });
  });

  group('talking to the home screen', () {
    const channel = MethodChannel('home_widget');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    late List<MethodCall> calls;
    late Directory support;

    setUp(() {
      calls = [];
      support = Directory.systemTemp.createTempSync('sky_widget_host_');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getWidgetData') return null;
        return true;
      });
      messenger.setMockMethodCallHandler(paths, (call) async => support.path);
    });

    tearDown(() {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(paths, null);
      support.deleteSync(recursive: true);
    });

    test('values are saved under the widget keys', () async {
      const host = HomeWidgetHost();
      await host.save(SkyWidgetKeys.label, '3 stars');
      await host.save(SkyWidgetKeys.night, true);
      expect(calls.map((call) => call.method), ['saveWidgetData', 'saveWidgetData']);
      expect(calls[0].arguments, {'id': SkyWidgetKeys.label, 'data': '3 stars'});
      expect(calls[1].arguments, {'id': SkyWidgetKeys.night, 'data': true});
    });

    test('the Android widget is asked to redraw by its provider name', () async {
      await const HomeWidgetHost().update();
      expect(calls.single.method, 'updateWidget');
      expect((calls.single.arguments as Map)['qualifiedAndroidName'], SkyWidgetKeys.provider);
    });

    test('pictures are written as files the widget can open', () async {
      final png = Uint8List.fromList([137, 80, 78, 71]);
      await const HomeWidgetHost().saveImage(SkyWidgetKeys.sky, png);
      final file = File('${support.path}/home_widget/${SkyWidgetKeys.sky}.png');
      expect(file.readAsBytesSync(), png);
      final saved = calls.singleWhere((call) => call.method == 'saveWidgetData');
      expect(saved.arguments, {'id': SkyWidgetKeys.sky, 'data': file.path});
    });
  });
}
