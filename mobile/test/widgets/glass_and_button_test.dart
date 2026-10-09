import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/theme/app_gradients.dart';
import 'package:our_space_mobile/presentation/theme/app_shadows.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/bouncy_button.dart';
import 'package:our_space_mobile/presentation/widgets/css_box.dart';
import 'package:our_space_mobile/presentation/widgets/glass_card.dart';
import 'package:our_space_mobile/presentation/widgets/lucide_icon.dart';

import 'harness.dart';

BoxDecoration _decorationOf(WidgetTester tester, Finder within) {
  final boxes = tester.widgetList<DecoratedBox>(find.descendant(of: within, matching: find.byType(DecoratedBox)));
  return boxes.map((b) => b.decoration).whereType<BoxDecoration>().first;
}

void main() {
  setUp(recordHaptics);

  group('GlassCard', () {
    testWidgets('renders the .glass-panel look with p-5 and rounded-3xl', (tester) async {
      await pumpHost(tester, const SizedBox(width: 300, child: GlassCard(child: Text('Together'))));
      expect(find.text('Together'), findsOneWidget);
      final decoration = _decorationOf(tester, find.byType(GlassCard));
      expect(decoration.color, AppColors.white.withValues(alpha: 0.72));
      expect((decoration.border as Border).top.color, AppColors.white.withValues(alpha: 0.85));
      expect(decoration.borderRadius, BorderRadius.circular(24));
      expect(find.descendant(of: find.byType(GlassCard), matching: find.byType(BackdropFilter)), findsOneWidget);
      final painter = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(GlassCard), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CssShadowPainter)),
      );
      expect((painter.painter! as CssShadowPainter).shadows, AppShadows.glassPanel);
      final textTopLeft = tester.getTopLeft(find.text('Together'));
      final cardTopLeft = tester.getTopLeft(find.byType(GlassCard));
      expect(textTopLeft - cardTopLeft, const Offset(21, 21));
    });

    testWidgets('blur can be turned off and taps are reported', (tester) async {
      var taps = 0;
      await pumpHost(tester, GlassCard(blur: false, onTap: () => taps++, child: const Text('Letter')));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('Letter'));
      expect(taps, 1);
    });
  });

  group('BouncyButton', () {
    testWidgets('primary variant uses the blush gradient, white semibold text-sm and fires a tick', (tester) async {
      var pressed = 0;
      await pumpHost(tester, BouncyButton(onPressed: () => pressed++, label: 'Pin it up 💕'));
      final decoration = _decorationOf(tester, find.byType(BouncyButton));
      expect(decoration.gradient, AppGradients.buttonPrimary);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      final text = tester.widget<Text>(find.text('Pin it up 💕'));
      expect(text.style?.fontSize, 14);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.color, AppColors.white);
      expect(tester.getSize(find.byType(BouncyButton)).height, 44);
      await tester.tap(find.byType(BouncyButton));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(recordedHaptics, [HapticKind.tick]);
    });

    testWidgets('variants map to the web colours', (tester) async {
      final expectations = <BouncyVariant, Color>{
        BouncyVariant.primary: AppColors.white,
        BouncyVariant.secondary: AppColors.blush600,
        BouncyVariant.matcha: AppColors.emerald800,
        BouncyVariant.lavender: AppColors.indigo900,
        BouncyVariant.ghost: AppColors.slate600,
      };
      for (final entry in expectations.entries) {
        expect(BouncyStyle.of(entry.key).foreground, entry.value, reason: '${entry.key}');
      }
      expect(BouncyStyle.of(BouncyVariant.secondary).border, isNotNull);
      expect(BouncyStyle.of(BouncyVariant.matcha).gradient, AppGradients.buttonMatcha);
      expect(BouncyStyle.of(BouncyVariant.lavender).gradient, AppGradients.buttonLavender);
      expect(BouncyStyle.of(BouncyVariant.ghost).shadows, isEmpty);
    });

    testWidgets('small pill with an icon matches text-xs rounded-full', (tester) async {
      await pumpHost(
        tester,
        BouncyButton(onPressed: () {}, small: true, pill: true, icon: AppIcons.plus, label: 'Snap Memory'),
      );
      final text = tester.widget<Text>(find.text('Snap Memory'));
      expect(text.style?.fontSize, 12);
      final decoration = _decorationOf(tester, find.byType(BouncyButton));
      expect(decoration.borderRadius, BorderRadius.circular(9999));
      final icon = tester.widget<LucideIcon>(find.byType(LucideIcon));
      expect(icon.size, 16);
      expect(icon.icon, AppIcons.plus);
      expect(tester.getSize(find.byType(BouncyButton)).height, 40);
    });

    testWidgets('disabled buttons fade to 50% and ignore taps', (tester) async {
      var pressed = 0;
      await pumpHost(tester, BouncyButton(onPressed: () => pressed++, enabled: false, label: 'Saving…'));
      await tester.tap(find.text('Saving…'), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
      expect(recordedHaptics, isEmpty);
      final opacity = tester.widget<Opacity>(find.descendant(of: find.byType(BouncyButton), matching: find.byType(Opacity)).first);
      expect(opacity.opacity, 0.5);
    });

    testWidgets('pressing springs the button down towards 0.94', (tester) async {
      await pumpHost(tester, BouncyButton(onPressed: () {}, label: 'Roll Another Date Idea'));
      final gesture = await tester.startGesture(tester.getCenter(find.byType(BouncyButton)));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
      final transform = tester.widget<Transform>(
        find.descendant(of: find.byType(BouncyButton), matching: find.byType(Transform)).first,
      );
      expect(transform.transform.storage[0], closeTo(0.94, 0.02));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('expand stretches to the full width like w-full', (tester) async {
      await pumpHost(tester, SizedBox(width: 320, child: BouncyButton(onPressed: () {}, expand: true, label: 'Unlock Our Space 💕')));
      expect(tester.getSize(find.byType(BouncyButton)).width, 320);
    });
  });
}
