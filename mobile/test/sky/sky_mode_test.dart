import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

void main() {
  test('day runs from six in the morning to six in the evening', () {
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 5, 59)), SkyMode.night);
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 6)), SkyMode.day);
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 12, 30)), SkyMode.day);
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 17, 59)), SkyMode.day);
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 18)), SkyMode.night);
    expect(SkyModeController.modeAt(DateTime(2026, 10, 22, 23, 30)), SkyMode.night);
  });

  test('the next change is the coming six o clock', () {
    expect(SkyModeController.nextChangeAfter(DateTime(2026, 10, 22, 3)), DateTime(2026, 10, 22, 6));
    expect(SkyModeController.nextChangeAfter(DateTime(2026, 10, 22, 9)), DateTime(2026, 10, 22, 18));
    expect(SkyModeController.nextChangeAfter(DateTime(2026, 10, 22, 20)), DateTime(2026, 10, 23, 6));
    expect(SkyModeController.nextChangeAfter(DateTime(2026, 12, 31, 22)), DateTime(2027, 1, 1, 6));
  });

  test('follows the time by default', () {
    final noon = SkyModeController(clock: () => DateTime(2026, 10, 22, 12), schedule: false);
    final midnight = SkyModeController(clock: () => DateTime(2026, 10, 22, 0, 30), schedule: false);
    expect(noon.followsTime, isTrue);
    expect(noon.mode, SkyMode.day);
    expect(noon.tokens, same(SkyTokens.day));
    expect(midnight.mode, SkyMode.night);
    expect(midnight.isNight, isTrue);
    noon.dispose();
    midnight.dispose();
  });

  test('turning following off keeps the night and is remembered on this phone', () async {
    final settings = LocalSettings.memory();
    final sky = SkyModeController(settings: settings, clock: () => DateTime(2026, 10, 22, 12), schedule: false);
    var notified = 0;
    sky.addListener(() => notified++);
    await sky.setFollowsTime(false);
    expect(sky.followsTime, isFalse);
    expect(sky.mode, SkyMode.night);
    expect(settings.getItem(SkyModeController.followsTimeKey), '0');
    expect(notified, 1);

    final again = SkyModeController(settings: settings, clock: () => DateTime(2026, 10, 22, 12), schedule: false);
    expect(again.followsTime, isFalse);
    expect(again.mode, SkyMode.night);

    await sky.setFollowsTime(true);
    expect(sky.mode, SkyMode.day);
    expect(settings.getItem(SkyModeController.followsTimeKey), '1');
    sky.dispose();
    again.dispose();
  });

  test('refresh only notifies when the sky changes', () {
    var now = DateTime(2026, 10, 22, 17, 0);
    final sky = SkyModeController(clock: () => now, schedule: false);
    var notified = 0;
    sky.addListener(() => notified++);
    sky.refresh();
    expect(notified, 0);
    now = DateTime(2026, 10, 22, 18, 1);
    sky.refresh();
    expect(notified, 1);
    expect(sky.mode, SkyMode.night);
    sky.dispose();
    sky.refresh();
    expect(notified, 1);
  });

  testWidgets('a timer turns the sky at the next boundary', (tester) async {
    var now = DateTime(2026, 10, 22, 17, 59);
    final sky = SkyModeController(clock: () => now);
    expect(sky.mode, SkyMode.day);
    now = DateTime(2026, 10, 22, 18, 0, 2);
    await tester.pump(const Duration(minutes: 1, seconds: 2));
    expect(sky.mode, SkyMode.night);
    sky.dispose();
  });

  testWidgets('the scope hands out the controller and refreshes when the app comes back', (tester) async {
    var now = DateTime(2026, 10, 22, 17, 0);
    final sky = SkyModeController(clock: () => now, schedule: false);
    addTearDown(sky.dispose);
    SkyModeController? seen;
    var builds = 0;
    await tester.pumpWidget(
      SkyModeScope(
        controller: sky,
        child: Builder(
          builder: (context) {
            builds++;
            seen = SkyModeScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(sky));
    now = DateTime(2026, 10, 22, 19, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(sky.mode, SkyMode.night);
    expect(builds, 2);
  });
}
