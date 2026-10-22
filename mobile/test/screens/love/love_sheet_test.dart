import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'love_harness.dart';

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

void main() {
  setUp(recordHaptics);

  test('the love sheet copy uses the partner name and pronoun', () {
    const she = PronounSet(
      subject: 'she',
      object: 'her',
      possessive: 'her',
      independent: 'hers',
      has: 'has',
      isVerb: 'is',
    );
    expect(LoveSheetCopy.forName('Alex'), 'For Alex');
    expect(LoveSheetCopy.reaches('Alex', she), 'It reaches Alex right away, wherever she is.');
  });

  testWidgets('the centre heart opens the love sheet and sends a love burst', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await untilFound(tester, find.byKey(ShellKeys.dock));

    await tester.tap(labelled(ShellCopy.sendLove));
    await settleRoute(tester);
    expect(find.text(LoveSheetCopy.title), findsOneWidget);
    expect(find.text('FOR ALEX'), findsOneWidget);
    expect(find.text('It reaches Alex right away, wherever she is.'), findsOneWidget);

    recordedHaptics.clear();
    await tester.tap(labelled(LoveSheetCopy.send));
    await tester.pump();
    expect(recordedHaptics, contains(HapticKind.celebration));
    final notices = tester.element(find.byType(LoveSheet)).read<AppNotices>();
    await until(tester, () => notices.toast.message == 'Saved 💕 Alex will see it the moment you two connect.');
    final bursts = await drive(tester, () => space.store.listDecrypted(loveBurstsTable, space.vault.requireKey()));
    expect(bursts, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(LoveSheetCopy.send.toUpperCase()), findsOneWidget);

    await tester.tapAt(const Offset(20, 60));
    await settleRoute(tester);
    expect(find.text(LoveSheetCopy.title), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester, space);
  });
}
