import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'sky_widget_art.dart';
import 'sky_widget_state.dart';

abstract class SkyWidgetHost {
  const SkyWidgetHost();

  Future<void> saveImage(String key, Uint8List png);

  Future<void> save(String key, Object? value);

  Future<void> update();
}

class HomeWidgetHost extends SkyWidgetHost {
  const HomeWidgetHost();

  @override
  Future<void> saveImage(String key, Uint8List png) => HomeWidget.saveFile(key, png, extension: 'png');

  @override
  Future<void> save(String key, Object? value) => HomeWidget.saveWidgetData<Object>(key, value);

  @override
  Future<void> update() => HomeWidget.updateWidget(qualifiedAndroidName: SkyWidgetKeys.provider);
}

class SkyWidgetPublisher {
  const SkyWidgetPublisher({this.host = const HomeWidgetHost(), this.art = const SkyWidgetArt()});

  final SkyWidgetHost host;
  final SkyWidgetArt art;

  static SkyWidgetPublisher? forPlatform() => !kIsWeb && Platform.isAndroid ? const SkyWidgetPublisher() : null;

  Future<void> publish(SkyWidgetState state) async {
    final images = await art.render(state);
    await host.saveImage(SkyWidgetKeys.sky, images.sky);
    final stars = images.stars;
    if (stars == null) {
      await host.save(SkyWidgetKeys.stars, null);
    } else {
      await host.saveImage(SkyWidgetKeys.stars, stars);
    }
    for (final entry in state.data.entries) {
      await host.save(entry.key, entry.value);
    }
    await host.update();
  }
}
