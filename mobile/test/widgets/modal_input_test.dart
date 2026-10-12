import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/our_header.dart';
import 'package:our_space_mobile/presentation/widgets/our_inputs.dart';
import 'package:our_space_mobile/presentation/widgets/our_modal.dart';

import 'harness.dart';

class _Launcher extends StatelessWidget {
  const _Launcher(this.onPressed);

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: () => onPressed(context), child: const Text('open'));
  }
}

void main() {
  setUp(recordHaptics);

  group('modals', () {
    testWidgets('showOurModal shows a white rounded card that the X closes', (tester) async {
      await pumpHost(
        tester,
        _Launcher((context) => showOurModal<void>(
              context: context,
              builder: (_) => const OurModalCard(
                child: OurModalHeader(
                  title: 'Add New Polaroid',
                  subtitle: 'Kept just between you two',
                  icon: AppIcons.sparkles,
                ),
              ),
            )),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add New Polaroid'), findsOneWidget);
      expect(find.text('Kept just between you two'), findsOneWidget);
      final card = tester.getSize(find.byType(OurModalCard));
      expect(card.width, lessThanOrEqualTo(384));
      await tester.tap(find.byType(OurCloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Add New Polaroid'), findsNothing);
    });

    testWidgets('backdrop taps only close when allowed, like the web overlays', (tester) async {
      await pumpHost(
        tester,
        _Launcher((context) => showOurModal<void>(
              context: context,
              builder: (_) => const OurModalCard(showClose: false, child: Text('Stay')),
            )),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Stay'), findsOneWidget);
    });

    testWidgets('showOurConfirm resolves true or false from the two buttons', (tester) async {
      final results = <bool>[];
      await pumpHost(
        tester,
        _Launcher((context) async => results.add(await showOurConfirm(context, message: 'Delete this milestone?'))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this milestone?'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [true, false]);
    });

    testWidgets('dialog actions show the busy label and block taps', (tester) async {
      var confirmed = 0;
      await pumpHost(
        tester,
        SizedBox(width: 320, child: OurDialogActions(confirmLabel: 'Save the copy', busy: true, onConfirm: () => confirmed++)),
      );
      expect(find.text('Working...'), findsOneWidget);
      expect(find.text('Save the copy'), findsNothing);
      await tester.tap(find.text('Working...'));
      expect(confirmed, 0);
    });

    testWidgets('the connect-device prompt keeps the web wording', (tester) async {
      final answers = <bool>[];
      await pumpHost(
        tester,
        _Launcher((context) async => answers.add(await showConnectDeviceDialog(context, peerId: 'our-space-abc123', fromLink: true))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to this device?'), findsOneWidget);
      expect(find.text('A link is asking to connect to the phone below.'), findsOneWidget);
      expect(find.text('our-space-abc123'), findsOneWidget);
      expect(find.text('Only connect if you know who sent you this link.'), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    test('pop entrance starts small and low, then springs to rest', () {
      final start = entranceFrameAt(OurModalEntrance.pop, 0);
      expect(start.opacity, 0);
      expect(start.scale, closeTo(0.9, 1e-9));
      expect(start.dy, closeTo(20, 1e-9));
      final end = entranceFrameAt(OurModalEntrance.pop, 0.45);
      expect(end.opacity, 1);
      expect(end.scale, closeTo(1, 0.01));
      expect(end.dy.abs(), lessThan(0.5));
      expect(entranceFrameAt(OurModalEntrance.sheet, 0).dy, closeTo(40, 1e-9));
    });
  });

  group('inputs', () {
    testWidgets('text field shows the hint, hides the passphrase and toggles it', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpHost(
        tester,
        SizedBox(
          width: 320,
          child: OurTextField(
            controller: controller,
            style: OurFieldStyle.lock,
            hint: 'Enter the secret phrase you both agreed on...',
            leadingIcon: AppIcons.keyRound,
            obscure: true,
          ),
        ),
      );
      expect(find.text('Enter the secret phrase you both agreed on...'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'moonlight');
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(find.bySemanticsLabel('Show passphrase'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      expect(controller.text, 'moonlight');
      expect(tester.getSize(find.byType(OurFieldFrame)).height, 46);
      handle.dispose();
    });

    testWidgets('focus draws a 2px ring outside the border', (tester) async {
      await pumpHost(tester, const SizedBox(width: 300, child: OurTextField(hint: 'Write your heart out...')));
      DecoratedBox? ring() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) => d.decoration is BoxDecoration && (d.decoration as BoxDecoration).border?.top.width == 2)
          .firstOrNull;
      expect(ring(), isNull);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final border = (ring()!.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, AppColors.blush400);
    });

    testWidgets('maxLength trims input without a counter', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpHost(tester, SizedBox(width: 300, child: OurTextField(controller: controller, maxLength: 5)));
      await tester.enterText(find.byType(TextField), 'abcdefgh');
      expect(controller.text, 'abcde');
      expect(find.textContaining('/5'), findsNothing);
    });

    testWidgets('date field shows mm/dd/yyyy and opens the picker', (tester) async {
      DateTime? picked;
      await pumpHost(
        tester,
        SizedBox(width: 300, child: OurDateField(value: DateTime(2026, 2, 14), onChanged: (d) => picked = d)),
      );
      expect(find.text('02/14/2026'), findsOneWidget);
      await tester.tap(find.byType(OurDateField));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2026, 2, 20));
      expect(formatInputDate(DateTime(2025, 1, 5)), '01/05/2025');
    });

    testWidgets('select field lists options and reports the choice', (tester) async {
      String? chosen;
      await pumpHost(
        tester,
        OurSelectField<String>(
          value: 'Romance',
          options: const [
            OurOption('Romance', 'Romance 💕'),
            OurOption('Travel', 'Travel ✈️'),
            OurOption('Adventures', 'Adventures 🌲'),
            OurOption('Silly', 'Silly & Fun 🤪'),
          ],
          onChanged: (v) => chosen = v,
        ),
      );
      expect(find.text('Romance 💕'), findsOneWidget);
      await tester.tap(find.byType(OurSelectField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel ✈️'));
      await tester.pumpAndSettle();
      expect(chosen, 'Travel');
    });

    testWidgets('segmented control and chips report selection', (tester) async {
      final picks = <String>[];
      await pumpHost(
        tester,
        SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OurSegmented<String>(
                segments: const [
                  OurSegment(value: 'setup', label: 'Create New Space', icon: AppIcons.sparkles),
                  OurSegment(value: 'join', label: "Join Partner's Space", icon: AppIcons.users),
                ],
                selected: 'setup',
                onChanged: picks.add,
              ),
              OurChip(label: 'At-Home', icon: AppIcons.home, selected: false, onTap: () => picks.add('chip')),
            ],
          ),
        ),
      );
      await tester.tap(find.text("Join Partner's Space"));
      await tester.tap(find.text('At-Home'));
      expect(picks, ['join', 'chip']);
    });
  });
}
