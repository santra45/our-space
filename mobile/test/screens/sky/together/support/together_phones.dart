import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_home.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../../../support/fake_sky_together.dart';

class FeltHaptic {
  const FeltHaptic(this.kind, this.shared);

  final HapticKind kind;
  final int shared;
}

class TogetherPhones {
  TogetherPhones({
    FakeSkyPair? pair,
    SkyDrawingService? drawingsA,
    VaultKey? keyA,
    SkyDrawingService? drawingsB,
    VaultKey? keyB,
  }) : pair = pair ?? FakeSkyPair(offsetB: 2500, latency: const Duration(milliseconds: 40)) {
    a = SkyTogetherHome(
      link: this.pair.a,
      drawings: drawingsA,
      keyOf: () => keyA,
      haptic: (kind) => feltA.add(FeltHaptic(kind, this.pair.a.sharedNow())),
      persistDelay: Duration.zero,
      nameEvery: Duration.zero,
    )..onOpen = openedA.add;
    b = SkyTogetherHome(
      link: this.pair.b,
      drawings: drawingsB,
      keyOf: () => keyB,
      haptic: (kind) => feltB.add(FeltHaptic(kind, this.pair.b.sharedNow())),
      persistDelay: Duration.zero,
      nameEvery: Duration.zero,
    )..onOpen = openedB.add;
  }

  final FakeSkyPair pair;
  late final SkyTogetherHome a;
  late final SkyTogetherHome b;
  final List<FeltHaptic> feltA = [];
  final List<FeltHaptic> feltB = [];
  final List<SkyPatchSession> openedA = [];
  final List<SkyPatchSession> openedB = [];

  List<HapticKind> kindsA() => [for (final f in feltA) f.kind];

  List<HapticKind> kindsB() => [for (final f in feltB) f.kind];

  Future<void> meet() async {
    pair.settle();
    await pumpEventQueue();
    pair.settle();
    await pumpEventQueue();
  }

  Future<void> step([Duration by = const Duration(milliseconds: 100)]) async {
    pair.advance(by);
    await pumpEventQueue();
    a.tick();
    b.tick();
    await pumpEventQueue();
  }

  Future<void> run(Duration total, {Duration step = const Duration(milliseconds: 100), bool Function()? until}) async {
    var left = total.inMilliseconds;
    while (left > 0) {
      if (until != null && until()) return;
      final ms = left < step.inMilliseconds ? left : step.inMilliseconds;
      await this.step(Duration(milliseconds: ms));
      left -= ms;
    }
  }

  Future<(SkyPatchSession, SkyPatchSession)> openTogether() async {
    final before = (openedA.length, openedB.length);
    a.press();
    await step();
    b.press();
    await run(
      const Duration(seconds: 14),
      until: () => openedA.length > before.$1 && openedB.length > before.$2,
    );
    expect(openedA.length, before.$1 + 1);
    expect(openedB.length, before.$2 + 1);
    await step();
    return (openedA.last, openedB.last);
  }

  Future<void> real(bool Function() done, {int tries = 400}) async {
    for (var i = 0; i < tries && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      pair.advance(const Duration(milliseconds: 10));
      await pumpEventQueue();
    }
    expect(done(), isTrue);
  }

  void dispose() {
    a.dispose();
    b.dispose();
    pair.dispose();
  }
}
