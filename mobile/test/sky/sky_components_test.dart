import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;

Widget skyApp(Widget child, {SkyTokens tokens = SkyTokens.night, bool animations = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(tokens),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
      child: app!,
    ),
    home: SkyTheme(
      child: Material(
        color: tokens.page,
        child: Center(child: child),
      ),
    ),
  );
}

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

class _Launcher extends StatelessWidget {
  const _Launcher(this.onPressed);

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => onPressed(context), child: const Text('open'));
}

void main() {
  setUp(recordHaptics);

  group('press feedback', () {
    testWidgets('scales down while pressed, springs back and ticks', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        skyApp(
          SkyPressable(onTap: () => taps++, semanticLabel: 'Press me', child: const SizedBox(width: 100, height: 40)),
          animations: true,
        ),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.byType(SkyPressable)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final pressed = tester.widget<Transform>(
        find.descendant(of: find.byType(SkyPressable), matching: find.byType(Transform)),
      );
      expect(pressed.transform.storage[0], closeTo(SkyMotion.pressScale, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      final released = tester.widget<Transform>(
        find.descendant(of: find.byType(SkyPressable), matching: find.byType(Transform)),
      );
      expect(released.transform.storage[0], closeTo(1, 0.001));
      expect(taps, 1);
      expect(recordedHaptics, [HapticKind.tick]);
      expect(labelled('Press me'), findsOneWidget);
    });

    testWidgets('does not scale when motion is reduced and ignores taps when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        skyApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyPressable(
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 40, child: Text('on')),
              ),
              SkyPressable(
                onTap: () => taps++,
                enabled: false,
                child: const SizedBox(width: 100, height: 40, child: Text('off')),
              ),
            ],
          ),
        ),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.text('on')));
      await tester.pump(const Duration(milliseconds: 200));
      final transform = tester.widget<Transform>(
        find.ancestor(of: find.text('on'), matching: find.byType(Transform)).first,
      );
      expect(transform.transform.storage[0], 1);
      await gesture.up();
      await tester.tap(find.text('off'));
      expect(taps, 1);
      expect(recordedHaptics, [HapticKind.tick]);
    });

    testWidgets('entrances fade in and settle at full opacity', (tester) async {
      for (final animations in [true, false]) {
        await tester.pumpWidget(
          skyApp(
            SkyEntrance(key: ValueKey<bool>(animations), index: 3, child: const Text('hello')),
            animations: animations,
          ),
        );
        final fade = tester.widget<FadeTransition>(
          find.ancestor(of: find.text('hello'), matching: find.byType(FadeTransition)).first,
        );
        expect(fade.opacity.value, lessThan(1));
        await tester.pumpAndSettle();
        expect(fade.opacity.value, 1);
      }
    });

    test('staggered children get rising indexes', () {
      final list = skyStaggered(const [Text('a'), Text('b'), Text('c')], startIndex: 2);
      expect(list.map((w) => (w as SkyEntrance).index), [2, 3, 4]);
    });
  });

  group('controls', () {
    testWidgets('buttons press, show busy and dim when disabled', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        skyApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyButton(label: 'Light the star', icon: SkyIcons.sparkle, onPressed: () => pressed++),
              const SkyButton(label: 'Saving', busy: true, busyLabel: 'Keeping it safe', onPressed: null),
              SkyButton(label: 'Ghost', variant: SkyButtonVariant.ghost, onPressed: () => pressed++),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Light the star'));
      await tester.tap(find.text('Keeping it safe'));
      await tester.tap(find.text('Ghost'));
      expect(pressed, 2);
      expect(find.byType(SkySpinner), findsOneWidget);
      final dim = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.text('Keeping it safe'), matching: find.byType(AnimatedOpacity)),
      );
      expect(dim.opacity, 0.5);
      final primary = tester.widget<Container>(
        find.ancestor(of: find.text('Light the star'), matching: find.byType(Container)).first,
      );
      expect((primary.decoration! as BoxDecoration).gradient, SkyTokens.night.primaryGradient);
    });

    testWidgets('icon buttons need a label and call back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        skyApp(
          SkyIconButton(
            icon: SkyIcons.pen,
            semanticLabel: 'Write a letter',
            tone: SkyIconButtonTone.rose,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(labelled('Write a letter'));
      expect(taps, 1);
      expect(tester.getSize(find.byType(SkyIconButton)), const Size(42, 42));
    });

    testWidgets('chips show their tone and report taps', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        skyApp(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyChip(label: 'Waiting', tone: SkyChipTone.on, onTap: () => tapped.add('w')),
              SkyChip(label: 'Opened', onTap: () => tapped.add('o')),
              const SkyChip(label: 'Romance', tone: SkyChipTone.rose, dense: true),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Opened'));
      await tester.pump();
      expect(tapped, ['o']);
      expect(tester.widget<Text>(find.text('Waiting')).style?.color, SkyTokens.night.activeFg);
      expect(tester.widget<Text>(find.text('Romance')).style?.color, SkyTokens.night.rose);
      expect(tester.widget<Semantics>(labelled('Waiting')).properties.selected, isTrue);
    });

    testWidgets('toggle flips, ticks and announces its state', (tester) async {
      var value = false;
      await tester.pumpWidget(
        skyApp(
          StatefulBuilder(
            builder: (context, setState) => SkyToggle(
              value: value,
              semanticLabel: 'Sky follows the time',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      expect(tester.widget<Semantics>(labelled('Sky follows the time')).properties.toggled, isFalse);
      await tester.tap(find.byType(SkyToggle));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(tester.widget<Semantics>(labelled('Sky follows the time')).properties.toggled, isTrue);
      expect(recordedHaptics, [HapticKind.tick]);
      final knob = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      expect(knob.alignment, Alignment.centerRight);
    });

    testWidgets('progress bar fills its share', (tester) async {
      await tester.pumpWidget(skyApp(const SizedBox(width: 200, child: SkyProgressBar(value: 0.25))));
      await tester.pumpAndSettle();
      final fill = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(fill.widthFactor, 0.25);
      await tester.pumpWidget(skyApp(const SizedBox(width: 200, child: SkyProgressBar(value: 4))));
      await tester.pumpAndSettle();
      expect(tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor, 1);
    });

    testWidgets('avatars take the first letter and change look by day', (tester) async {
      expect(SkyAvatar.initialOf('qalbi'), 'Q');
      expect(SkyAvatar.initialOf('  '), 'Q');
      expect(SkyAvatar.initialOf(null, fallback: 'O'), 'O');
      await tester.pumpWidget(skyApp(const SkyAvatar(initial: 'Q'), tokens: SkyTokens.day));
      await tester.pumpAndSettle();
      final day = tester.widget<Container>(find.ancestor(of: find.text('Q'), matching: find.byType(Container)).first);
      expect((day.decoration! as BoxDecoration).gradient, isNotNull);
      await tester.pumpWidget(skyApp(const SkyAvatar(initial: 'F', style: SkyAvatarStyle.partner)));
      await tester.pumpAndSettle();
      final night = tester.widget<Container>(find.ancestor(of: find.text('F'), matching: find.byType(Container)).first);
      expect((night.decoration! as BoxDecoration).color, const Color(0xFF181335));
      expect(tester.widget<Text>(find.text('F')).style?.color, const Color(0xFFFFB6CB));
    });

    testWidgets('text fields show hints, labels and hide passphrases', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        skyApp(
          SizedBox(
            width: 300,
            child: SkyTextField(
              controller: controller,
              label: 'Title',
              helper: 'Shows while sealed',
              hint: 'Open when',
              obscure: true,
            ),
          ),
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Shows while sealed'), findsOneWidget);
      expect(find.text('Open when'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(labelled('Show'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      await tester.enterText(find.byType(TextField), 'you miss me');
      expect(controller.text, 'you miss me');
    });
  });

  group('surfaces', () {
    testWidgets('list rows show icon, value and chevron and are tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        skyApp(
          SizedBox(
            width: 340,
            child: SkyListGroup(
              label: 'The two of us',
              children: [
                SkyListRow(icon: SkyIcons.pen, title: 'Names', value: 'Qalbi & Farhu', onTap: () => taps++),
                const SkyListRow(
                  icon: SkyIcons.moon,
                  tone: SkyTone.lavender,
                  title: 'Sky follows the time',
                  subtitle: 'Day sky by day',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('THE TWO OF US'), findsOneWidget);
      expect(find.text('Qalbi & Farhu'), findsOneWidget);
      await tester.tap(find.text('Names'));
      expect(taps, 1);
      final chevrons = tester.widgetList<SkyIcon>(find.byType(SkyIcon)).where((i) => i.icon == SkyIcons.chevron);
      expect(chevrons, hasLength(1));
      expect(find.byType(SkyDivider), findsOneWidget);
    });

    testWidgets('notices offer an action and a dismiss', (tester) async {
      var acted = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        skyApp(
          SizedBox(
            width: 340,
            child: SkyNotice(
              text: '2 letters are hidden for now.',
              tone: SkyNoticeTone.warning,
              actionLabel: 'Why',
              onAction: () => acted++,
              onDismiss: () => dismissed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Why'));
      await tester.tap(labelled('Dismiss'));
      expect(acted, 1);
      expect(dismissed, 1);
    });

    testWidgets('empty and error states speak warmly and offer a way forward', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        skyApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SkyEmptyState(title: 'No letters yet', message: 'Write the first one tonight.'),
              SkyErrorState(onRetry: () => retried++),
            ],
          ),
        ),
      );
      expect(find.text('No letters yet'), findsOneWidget);
      expect(find.text('Something went quiet'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('top bar uppercases the kicker and labels and tips render', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        skyApp(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyTopBar(kicker: 'Night 28 · Wednesday', title: 'Our sky, tonight'),
              SkyLabel("Tonight's question", icon: SkyIcons.sparkle, tone: SkyTone.rose),
              SkyTip(text: 'A letter fell from the sky', icon: SkyIcons.letter),
              SkyTip.two(title: "Tonight's star", subtitle: 'answer to light it'),
              SkyNameLabel('Farhu'),
              SkyHereChip(),
            ],
          ),
        ),
      );
      expect(find.text('NIGHT 28 · WEDNESDAY'), findsOneWidget);
      expect(find.text('Our sky, tonight'), findsOneWidget);
      expect(find.text("TONIGHT'S QUESTION"), findsOneWidget);
      expect(find.text('answer to light it'), findsOneWidget);
      expect(find.text('here now'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Our sky, tonight')).style?.fontFamily, SkyFonts.serif);
    });

    testWidgets('scroll scaffold keeps content above the bottom inset', (tester) async {
      usePhoneSize(tester, bottom: 16);
      late double inset;
      await tester.pumpWidget(
        skyApp(
          Builder(
            builder: (context) {
              inset = SkyScrollScaffold.bottomInsetOf(context);
              return SkyScrollScaffold(
                topBar: const SkyTopBar(title: 'Letters', kicker: 'Fallen from the sky'),
                children: [for (var i = 0; i < 3; i++) SizedBox(height: 40, child: Text('row $i'))],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(inset, 16 + SkySpace.xl);
      expect(find.text('row 2'), findsOneWidget);
      expect(find.text('FALLEN FROM THE SKY'), findsOneWidget);
    });
  });

  group('overlays', () {
    test('calm text drops emoji and keeps sentences readable', () {
      expect(skyCalmText('Saved 💕 your partner will see it.'), 'Saved. Your partner will see it.');
      expect(skyCalmText('Love burst sent to Alex! 💕'), 'Love burst sent to Alex!');
      expect(skyCalmText('Phone to phone ⚡'), 'Phone to phone');
      expect(skyCalmText('Our Space 💕 ✨ yay'), 'Our Space. Yay');
      expect(skyCalmText('No emoji here.'), 'No emoji here.');
      expect(skyCalmText('💕'), '');
    });

    testWidgets('sheets slide up with a grab handle and close from the barrier', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        skyApp(
          _Launcher(
            (context) => showSkySheet<void>(context: context, builder: (_) => const Text('Send a little love')),
          ),
          animations: true,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Send a little love'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(SkyGrabHandle), findsOneWidget);
      expect(find.byType(SkySheet), findsOneWidget);
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
      expect(find.text('Send a little love'), findsNothing);
    });

    testWidgets('sheets close when dragged down', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        skyApp(
          _Launcher(
            (context) => showSkySheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 300, child: Text('drag me')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('drag me'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('drag me'), findsNothing);
    });

    testWidgets('a sheet that may not close springs back when dragged and can be dragged again', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        skyApp(
          _Launcher(
            (context) => showSkySheet<void>(
              context: context,
              builder: (_) => const PopScope(canPop: false, child: SizedBox(height: 300, child: Text('stay'))),
            ),
          ),
          animations: true,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      double top() => tester.getTopLeft(find.byType(SkySheet)).dy;
      final rest = top();

      await tester.fling(find.text('stay'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('stay'), findsOneWidget);
      expect(top(), moreOrLessEquals(rest, epsilon: 0.5));

      final gesture = await tester.startGesture(tester.getCenter(find.text('stay')));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(top(), greaterThan(rest + 30));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('stay'), findsOneWidget);
      expect(top(), moreOrLessEquals(rest, epsilon: 0.5));
    });

    testWidgets('confirm resolves yes and not now', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        skyApp(
          _Launcher(
            (context) async => answers.add(
              await showSkyConfirm(
                context,
                title: 'Let this letter go?',
                message: 'It leaves both phones.',
                destructive: true,
                confirmLabel: 'Let it go',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Let this letter go?'), findsOneWidget);
      expect(find.text('It leaves both phones.'), findsOneWidget);
      await tester.tap(find.text('Let it go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(answers, [true, false]);
    });

    testWidgets('the toast host shows calm text and clears on tap', (tester) async {
      final controller = SkyToastController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(skyApp(SizedBox(width: 340, child: SkyToastHost(controller: controller))));
      controller.show('Love burst sent to Alex! 💕');
      await tester.pump();
      expect(find.text('Love burst sent to Alex!'), findsOneWidget);
      await tester.tap(find.text('Love burst sent to Alex!'));
      await tester.pump();
      expect(controller.message, isNull);
      expect(find.text('Love burst sent to Alex!'), findsNothing);
    });

    testWidgets('SkyToast uses the scoped controller when there is one', (tester) async {
      final controller = SkyToastController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        skyApp(
          SkyToastScope(
            controller: controller,
            child: Builder(
              builder: (context) =>
                  TextButton(onPressed: () => SkyToast.show(context, 'Kept safe'), child: const Text('go')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      expect(controller.message, 'Kept safe');
      controller.clear();
    });

    testWidgets('SkyToast falls back to an overlay pill', (tester) async {
      await tester.pumpWidget(
        skyApp(
          Builder(
            builder: (context) =>
                TextButton(onPressed: () => SkyToast.show(context, 'Saved 💕'), child: const Text('go')),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Saved'), findsNothing);
    });
  });
}
