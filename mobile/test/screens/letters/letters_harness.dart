import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_shelf.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_keys.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../capsule/capsule_harness.dart';

export '../capsule/capsule_harness.dart'
    show
        buttonEnabled,
        calm,
        inDays,
        openReadySpace,
        openStrangerSpace,
        openTab,
        press,
        real,
        reveal,
        settleRoutes,
        typeInto,
        until,
        untilFound,
        untilGone;

int _seeded = 0;

Future<void> keepNightSky(WidgetTester tester, OurSpace space) =>
    real(tester, () => space.store.settings.setItem(SkyModeController.followsTimeKey, '0'));

Future<void> openLetters(WidgetTester tester, OurSpace space) async {
  await keepNightSky(tester, space);
  await openTab(tester, space, 'Letters');
  await tester.pump(SkyMotion.dayNight + const Duration(milliseconds: 100));
}

Future<String> seedLetter(
  WidgetTester tester,
  OurSpace space, {
  required String title,
  String content = 'With all my love.',
  DateTime? written,
  bool opened = false,
  DateTime? openedAt,
  String? unlockDate,
  bool mine = false,
}) async {
  final id = 'let-seed-${_seeded++}';
  final at = (written ?? DateTime.now()).millisecondsSinceEpoch;
  await real(
    tester,
    () => space.letters.write({
      'id': id,
      'title': title,
      'content': content,
      'unlockDate': unlockDate,
      'isOpened': opened,
      if (opened) 'openedAt': (openedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'createdAt': at,
      'updatedAt': at,
      'deleted': false,
    }),
  );
  if (mine) await real(tester, () => LettersWrittenHere.remember(space.store.settings, id));
  return id;
}

Future<T> drive<T>(WidgetTester tester, Future<T> Function() body) async {
  late T value;
  Object? failure;
  var done = false;
  body().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  await until(tester, () => done);
  if (failure != null) throw failure!;
  return value;
}

Future<List<LetterRecord>> lettersOnceThey(
  WidgetTester tester,
  OurSpace space,
  bool Function(List<LetterRecord> letters) done,
) async {
  var letters = await drive(tester, space.letters.list);
  for (var i = 0; i < 100 && !done(letters); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    letters = await drive(tester, space.letters.list);
  }
  return letters;
}

Finder textFieldIn(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(TextField));

Finder labelled(String label) => find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

bool sealEnabled(WidgetTester tester) => tester.widget<SkyButton>(find.byKey(LettersKeys.sealButton)).enabled;

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(seconds: 2));
  }
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 5));
  }
}
