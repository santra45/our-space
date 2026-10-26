import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_host.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_state.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_sync.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../support/harness.dart';

const String passphrase = 'correct horse battery staple 2026';
const int fastIterations = 1000;
const int dayMs = 86400000;

Future<OurSpace> openSpace() {
  final dir = Directory.systemTemp.createTempSync('our_space_widget_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
  );
}

Future<OurSpace> coupleSpace() async {
  final space = await openSpace();
  await space.vault.create(passphrase: passphrase, coupleNames: 'Sam & Alex', iterations: fastIterations);
  await space.identity.createCouple(myName: 'Sam', partnerName: 'Alex', partnerPronoun: 'she');
  await space.identity.refresh();
  return space;
}

Future<void> iAnswer(OurSpace space, {int? when}) async {
  final key = space.vault.requireKey();
  await space.dailyQuestion.saveAnswer(
    key,
    ownerId: space.identity.myOwnerId,
    ownerIds: space.identity.myOwnerIds,
    questionId: space.dailyQuestion.questionForDay(key, when).question.id,
    text: 'Sam thinks of Alex',
    when: when,
  );
}

Future<void> partnerAnswers(OurSpace space, {int? when}) async {
  final key = space.vault.requireKey();
  await space.dailyQuestion.saveAnswer(
    key,
    ownerId: space.identity.partner!.personId,
    questionId: space.dailyQuestion.questionForDay(key, when).question.id,
    text: 'Alex thinks of Sam',
    when: when,
  );
}

Future<void> pastNights(OurSpace space, int count) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 1; i <= count; i++) {
    await iAnswer(space, when: now - i * dayMs);
    await partnerAnswers(space, when: now - i * dayMs);
  }
}

Future<void> eventually(bool Function() done, {int tries = 600}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

Future<void> quiet() => Future<void>.delayed(const Duration(milliseconds: 250));

class Clock {
  DateTime now = DateTime(2026, 10, 26, 21);

  DateTime call() => now;
}

class Shown {
  final List<SkyWidgetState> states = [];
  int failures = 0;

  SkyWidgetState? get last => states.isEmpty ? null : states.last;

  Future<void> call(SkyWidgetState state) async {
    if (failures > 0) {
      failures--;
      throw StateError('The home screen was busy.');
    }
    states.add(state);
  }
}

class RecordingPublisher extends SkyWidgetPublisher {
  RecordingPublisher();

  final List<SkyWidgetState> states = [];

  @override
  Future<void> publish(SkyWidgetState state) async => states.add(state);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Clock clock;
  late SkyModeController sky;
  late Shown shown;
  final opened = <OurSpace>[];
  final syncs = <SkyWidgetSync>[];

  setUp(() {
    clock = Clock();
    sky = SkyModeController(settings: LocalSettings.memory(), clock: clock.call, schedule: false);
    shown = Shown();
  });

  tearDown(() async {
    for (final sync in syncs) {
      sync.dispose();
    }
    syncs.clear();
    sky.dispose();
    await quiet();
    for (final space in opened) {
      await space.close();
    }
    opened.clear();
  });

  SkyWidgetSync follow(OurSpace space) {
    opened.add(space);
    final sync = SkyWidgetSync(space: space, sky: sky, show: shown.call)..start();
    syncs.add(sync);
    return sync;
  }

  group('when the widget is updated', () {
    test('a phone with no space yet shows the calm empty sky', () async {
      final space = await openSpace();
      expect(space.vault.isInitialized, isFalse);
      follow(space);
      await eventually(() => shown.states.isNotEmpty);
      await quiet();
      expect(shown.states, [const SkyWidgetState.empty()]);
      expect(shown.last!.label, 'Our Space');
    });

    test('opening the space shows the stars you already share', () async {
      final space = await coupleSpace();
      await pastNights(space, 3);
      final sync = follow(space);
      await eventually(() => shown.last?.stars == 3);
      await quiet();
      expect(shown.states, hasLength(1));
      expect(shown.last!.label, '3 stars');
      expect(shown.last!.night, isTrue);
      expect(shown.last!.constellation!.litPoints, hasLength(3));
      expect(sync.shown, shown.last);
    });

    test('a space with no shared nights yet is still the empty sky', () async {
      final space = await coupleSpace();
      follow(space);
      await eventually(() => shown.states.isNotEmpty);
      await quiet();
      expect(shown.states, [const SkyWidgetState.empty()]);
    });

    test('answering alone changes nothing, and the partner answer lights the star', () async {
      final space = await coupleSpace();
      await pastNights(space, 2);
      follow(space);
      await eventually(() => shown.last?.stars == 2);
      await iAnswer(space);
      await quiet();
      expect(shown.states, hasLength(1));
      await partnerAnswers(space);
      await eventually(() => shown.last?.stars == 3);
      expect(shown.states, hasLength(2));
      expect(shown.last!.label, '3 stars');
    });

    test('the sky turns to day and back with the same stars', () async {
      final space = await coupleSpace();
      await pastNights(space, 4);
      follow(space);
      await eventually(() => shown.last?.stars == 4);
      final night = shown.last!;
      clock.now = DateTime(2026, 10, 27, 9);
      sky.refresh();
      await eventually(() => shown.states.length == 2);
      expect(shown.last, night.inMode(night: false));
      clock.now = DateTime(2026, 10, 27, 19);
      sky.refresh();
      await eventually(() => shown.states.length == 3);
      expect(shown.last, night);
    });

    test('a locked space keeps its sky and still follows day and night', () async {
      final space = await coupleSpace();
      await pastNights(space, 5);
      follow(space);
      await eventually(() => shown.last?.stars == 5);
      space.vault.lock();
      await quiet();
      expect(shown.states, hasLength(1));
      clock.now = DateTime(2026, 10, 27, 9);
      sky.refresh();
      await eventually(() => shown.states.length == 2);
      expect(shown.last!.night, isFalse);
      expect(shown.last!.stars, 5);
    });

    test('unlocking again shows what happened while it was locked', () async {
      final space = await coupleSpace();
      await pastNights(space, 1);
      follow(space);
      await eventually(() => shown.last?.stars == 1);
      final key = space.vault.requireKey();
      final me = space.identity.myOwnerId;
      final mine = space.identity.myOwnerIds;
      final partner = space.identity.partner!.personId;
      final question = space.dailyQuestion.questionForDay(key).question.id;
      space.vault.lock();
      await space.dailyQuestion.saveAnswer(key, ownerId: me, ownerIds: mine, questionId: question, text: 'Sam');
      await space.dailyQuestion.saveAnswer(key, ownerId: partner, questionId: question, text: 'Alex');
      await quiet();
      expect(shown.states, hasLength(1));
      await space.vault.unlockWithKey(key, iterations: fastIterations);
      await eventually(() => shown.last?.stars == 2);
      expect(shown.states, hasLength(2));
    });

    test('a space that is erased and started again goes back to the empty sky', () async {
      final space = await coupleSpace();
      await pastNights(space, 6);
      follow(space);
      await eventually(() => shown.last?.stars == 6);
      space.vault.lock();
      final result = await space.vault.create(
        passphrase: 'a completely different passphrase',
        confirmDestroy: destroyConfirmationPhrase,
        iterations: fastIterations,
      );
      expect(result.ok, isTrue);
      await eventually(() => shown.last == const SkyWidgetState.empty());
      expect(shown.states, [shown.states.first, const SkyWidgetState.empty()]);
    });

    test('a failed update is tried again with the next change', () async {
      final space = await coupleSpace();
      await pastNights(space, 2);
      shown.failures = 1;
      follow(space);
      await eventually(() => shown.failures == 0);
      await quiet();
      await iAnswer(space);
      await partnerAnswers(space);
      await eventually(() => shown.last?.stars == 3);
      expect(shown.states.where((state) => state.stars == 2).length, lessThanOrEqualTo(1));
    });

    test('nothing is sent twice in a row', () async {
      final space = await coupleSpace();
      await pastNights(space, 2);
      follow(space);
      await eventually(() => shown.last?.stars == 2);
      await space.identity.refresh();
      sky.refresh(force: true);
      await iAnswer(space);
      await quiet();
      expect(shown.states, hasLength(1));
    });

    test('once stopped it no longer follows the space', () async {
      final space = await coupleSpace();
      final sync = follow(space);
      await eventually(() => shown.states.isNotEmpty);
      sync.dispose();
      await pastNights(space, 2);
      clock.now = DateTime(2026, 10, 27, 9);
      sky.refresh();
      await quiet();
      expect(shown.states, [const SkyWidgetState.empty()]);
      await sync.settled();
    });
  });

  group('in the app', () {
    testWidgets('the open app keeps the widget in step with the space', (tester) async {
      final space = (await tester.runAsync(coupleSpace))!;
      await tester.runAsync(() => pastNights(space, 2));
      final publisher = RecordingPublisher();
      await tester.pumpWidget(
        OurSpaceApp(openSpace: () async => space, shell: const SizedBox.shrink(), skyWidget: publisher),
      );
      for (var i = 0; i < 300 && (publisher.states.isEmpty || publisher.states.last.stars != 2); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(publisher.states.last.label, '2 stars');
      expect(publisher.states.where((state) => state.stars == 2), hasLength(1));
    });
  });
}
