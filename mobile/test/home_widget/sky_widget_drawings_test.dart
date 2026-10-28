import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_sync.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import 'sky_widget_sync_test.dart' show Clock, Shown, coupleSpace, eventually, pastNights, quiet;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a drawn constellation, finished or not, never reaches the home screen widget', () async {
    final clock = Clock();
    final sky = SkyModeController(settings: LocalSettings.memory(), clock: clock.call, schedule: false);
    final shown = Shown();
    final space = await coupleSpace();
    await pastNights(space, 3);
    final sync = SkyWidgetSync(space: space, sky: sky, show: shown.call)..start();
    await eventually(() => shown.last?.stars == 3);
    await quiet();
    final before = shown.last!;

    final key = space.vault.requireKey();
    final owner = space.identity.myOwnerId!;
    final drawing = SkyDrawing(
      stars: [
        SkyDrawnStar(id: 's-1', x: 0.3, y: 0.3, by: owner, at: 1, gen: 0),
        SkyDrawnStar(id: 's-2', x: 0.7, y: 0.6, by: owner, at: 2, gen: 0),
      ],
      lines: [SkyDrawnLine(from: 's-1', to: 's-2', by: owner, at: 3, gen: 0)],
    );
    await space.skyDrawings.saveProgress(key, id: 'sky-open', drawing: drawing);
    await space.skyDrawings.finish(key, id: 'sky-done', drawing: drawing, name: 'Our secret kite');
    await space.identity.refresh();
    await quiet();

    expect(shown.states, [before]);
    expect(shown.last!.data.keys.toSet(), before.data.keys.toSet());
    expect(shown.last!.data.values.join(' ').contains('kite'), isFalse);
    expect(shown.last!.stars, 3);

    sync.dispose();
    sky.dispose();
    await quiet();
    await space.close();
  });
}
