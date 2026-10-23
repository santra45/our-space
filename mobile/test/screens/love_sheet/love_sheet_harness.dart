import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/screens/love/widgets/love_heart.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';

import '../love/love_harness.dart';

export '../love/love_harness.dart';

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Finder heartFor(String name) => labelled(LoveSheetCopy.sendTo(name));

Finder noteSays(String text) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText(includePlaceholders: false) == text,
    );

Future<void> openLoveSheet(WidgetTester tester) async {
  await untilFound(tester, find.byKey(ShellKeys.dock));
  await tester.tap(labelled(ShellCopy.sendLove));
  await settleRoute(tester);
  expect(find.byType(LoveSheet), findsOneWidget);
}

Future<void> holdHeart(WidgetTester tester, String? name, {Duration? extra}) async {
  final target = name == null ? find.byType(LoveHeart) : heartFor(name);
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump();
  await tester.pump(LoveHeart.holdDuration + const Duration(milliseconds: 40));
  await tester.pump();
  if (extra != null) await tester.pump(extra);
  await gesture.up();
  await tester.pump();
}

AppNotices noticesOf(WidgetTester tester) => tester.element(find.byType(LoveSheet)).read<AppNotices>();

Future<void> untilToast(WidgetTester tester, bool Function(String message) matches) {
  final notices = noticesOf(tester);
  return until(tester, () {
    final message = notices.toast.message;
    return message != null && matches(message);
  });
}

Future<List<Map<String, Object?>>> bursts(WidgetTester tester, OurSpace space) =>
    drive(tester, () => space.store.listDecrypted(loveBurstsTable, space.vault.requireKey()));

Future<void> putBurst(WidgetTester tester, OurSpace space, String id, {required int count, required int at}) {
  return drive(
    tester,
    () => space.store.putEncrypted(
      loveBurstsTable,
      {'id': id, 'count': count, 'lastSentAt': at, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      space.vault.requireKey(),
    ),
  );
}

Future<void> partnerSendsLove(WidgetTester tester, OurSpace space, {required int count, required int at}) =>
    putBurst(tester, space, 'burst-alex-phone', count: count, at: at);

Future<void> closeLoveSheet(WidgetTester tester, OurSpace space) async {
  await tester.tapAt(const Offset(20, 60));
  await settleRoute(tester);
  expect(find.byType(LoveSheet), findsNothing);
  await tester.pump(const Duration(seconds: 5));
  await settle(tester, space);
}

Widget heartHost(Widget child, {SkyTokens tokens = SkyTokens.night, bool animations = true}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(tokens),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
      child: app!,
    ),
    home: SkyTheme(
      child: Material(color: tokens.page, child: Center(child: child)),
    ),
  );
}

Widget sheetHost(OurSpace space, {SkyTokens tokens = SkyTokens.night, Widget sheet = const LoveSheet()}) {
  return SpaceScope(
    space: space,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SkyThemes.legacy(tokens),
      home: SkyTheme(
        child: Material(
          color: tokens.surface,
          child: Align(alignment: Alignment.bottomCenter, child: sheet),
        ),
      ),
    ),
  );
}
