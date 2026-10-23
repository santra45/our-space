import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/bucket_copy.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/dream_row.dart';
import 'package:our_space_mobile/presentation/screens/lock/widgets/lock_fields.dart';
import 'package:our_space_mobile/presentation/screens/lock/widgets/lock_parts.dart';
import 'package:our_space_mobile/presentation/screens/roulette/date_roulette.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/settings_field.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/sheet_parts.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_stats.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../widgets/harness.dart' show recordHaptics;

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Widget host(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(SkyTokens.night),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: app!,
    ),
    home: SkyTheme(
      child: Material(
        color: SkyTokens.night.page,
        child: SingleChildScrollView(
          child: Center(child: SizedBox(width: 360, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  setUp(recordHaptics);

  testWidgets('links, text actions, dreams, date chips, stats and eye toggles answer a 44 point tap', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final tapped = <String>[];
    final settingsPassphrase = TextEditingController(text: 'secret');
    final lockPassphrase = TextEditingController(text: 'secret');
    addTearDown(settingsPassphrase.dispose);
    addTearDown(lockPassphrase.dispose);
    final dream = BucketListRecord({'id': 'dream-1', 'text': 'See the northern lights', 'completed': false});

    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction(label: 'Why?', small: true, onTap: () => tapped.add('Why?')),
            ),
            LockLink(label: 'Go back', onTap: () => tapped.add('Go back')),
            DreamRow(
              item: dream,
              onToggle: () => tapped.add('See the northern lights'),
              onOpen: () => tapped.add(BucketCopy.change),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: DateIdeaChip(label: 'Cozy', selected: false, onTap: () => tapped.add('Cozy')),
            ),
            SkyStatsRow(
              stats: [
                SkyStat(
                  key: const ValueKey<String>('stars'),
                  icon: SkyIcons.star,
                  value: '3',
                  label: 'stars joined',
                  valueColor: SkyTokens.night.gold,
                  onTap: () => tapped.add('3 stars joined'),
                ),
              ],
            ),
            SettingsField(
              controller: settingsPassphrase,
              hint: 'Passphrase',
              obscured: true,
              onToggleReveal: () => tapped.add(SettingsFieldCopy.show),
            ),
            LockField(controller: lockPassphrase, hint: 'Passphrase', obscure: true),
          ],
        ),
      ),
    );

    final labels = [
      'Why?',
      'Go back',
      'See the northern lights',
      BucketCopy.change,
      'Cozy',
      '3 stars joined',
      SettingsFieldCopy.show,
    ];
    for (final label in labels) {
      final area = tester.getRect(labelled(label));
      expect(area.height, greaterThanOrEqualTo(44), reason: label);
      await tester.tapAt(area.topLeft + const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tapped.last, label, reason: label);
    }
    expect(tapped, labels);

    final eye = tester.getRect(labelled(LockField.show));
    expect(eye.height, greaterThanOrEqualTo(44));
    expect(eye.width, greaterThanOrEqualTo(44));
    await tester.tapAt(eye.topLeft + const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(labelled(LockField.hide), findsOneWidget);
  });
}
