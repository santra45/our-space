import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart' show recordHaptics;
import '../love/love_harness.dart';

Future<void> openSettingsFromAvatar(WidgetTester tester) async {
  await untilFound(tester, find.byKey(ShellKeys.avatar));
  await tester.tap(find.byKey(ShellKeys.avatar));
  await settleRoute(tester);
  expect(find.byType(SettingsPage), findsOneWidget);
}

void main() {
  setUp(recordHaptics);

  testWidgets('settings opens from her avatar and shows the two of them', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openSettingsFromAvatar(tester);
    expect(find.text('Sam & Alex'), findsOneWidget);
    expect(find.text(SettingsCopy.since('Jun 14, 2021')), findsOneWidget);
    expect(find.text('S'), findsWidgets);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.bySemanticsLabelWidget('Back'));
    await settleRoute(tester);
    expect(find.byType(SettingsPage), findsNothing);
    await settle(tester, space);
  });

  testWidgets('turning off sky follows the time keeps the night and is remembered', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openSettingsFromAvatar(tester);
    final sky = SkyModeScope.of(tester.element(find.byType(SettingsPage)));
    expect(sky.followsTime, isTrue);

    await press(tester, find.byKey(ShellKeys.skyFollowsTime));
    await tester.pump(const Duration(seconds: 1));
    expect(sky.followsTime, isFalse);
    expect(sky.mode, SkyMode.night);
    expect(space.store.settings.getItem(SkyModeController.followsTimeKey), '0');
    expect(tester.widget<SkyToggle>(find.byKey(ShellKeys.skyFollowsTime)).value, isFalse);
    expect(Theme.of(tester.element(find.byType(SettingsPage))).extension<SkyTokens>()?.mode, SkyMode.night);

    await press(tester, find.byKey(ShellKeys.skyFollowsTime));
    await tester.pump(const Duration(seconds: 1));
    expect(space.store.settings.getItem(SkyModeController.followsTimeKey), '1');
    await settle(tester, space);
  });

  testWidgets('the lock button locks the space and closes settings', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openSettingsFromAvatar(tester);
    expect(find.text(SettingsCopy.phones), findsOneWidget);

    await press(tester, find.byKey(ShellKeys.lockNow));
    await settleRoute(tester);
    expect(space.vault.isUnlocked, isFalse);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
  });
}

extension on CommonFinders {
  Finder bySemanticsLabelWidget(String label) =>
      byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);
}
