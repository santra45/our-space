import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/lucide_icon.dart';
import 'package:our_space_mobile/presentation/widgets/our_bottom_nav.dart';
import 'package:our_space_mobile/presentation/widgets/our_feedback.dart';
import 'package:our_space_mobile/presentation/widgets/our_header.dart';

import 'harness.dart';

void main() {
  setUp(recordHaptics);

  group('OurHeader', () {
    testWidgets('falls back to Our Space and the Just for us line', (tester) async {
      await pumpHost(tester, const OurHeader(), scaffold: true);
      expect(find.text('Our Space'), findsOneWidget);
      expect(find.text('Just for us 💕'), findsOneWidget);
      expect(find.bySemanticsLabel('Tap to Pair'), findsOneWidget);
      expect(find.bySemanticsLabel('Lock Our Space'), findsOneWidget);
      expect(find.text('Tap to Pair'), findsNothing);
    });

    test('presence lines reuse the web copy', () {
      expect(const HeaderPresence.activeNow(partnerName: 'Sam').text, 'Sam active now 💕');
      expect(const HeaderPresence.activeNow().text, 'Active together 💕');
      expect(const HeaderPresence.lastSeen(partnerName: 'Sam', lastSeen: '5m ago').text, 'Sam • 5m ago');
      expect(const HeaderPresence.lastSeen(lastSeen: 'Yesterday').text, 'Active Yesterday');
      expect(const HeaderPresence.justForUs().text, 'Just for us 💕');
    });

    test('sync pill states mirror getStatusDisplay', () {
      expect(SyncPillStyle.of(SyncPillState.error).label, 'Sync hiccup');
      expect(SyncPillStyle.of(SyncPillState.direct).label, 'Phone to phone ⚡');
      expect(SyncPillStyle.of(SyncPillState.relayed).label, 'Via a helper 🛡️');
      expect(SyncPillStyle.of(SyncPillState.connected).label, 'Connected 💕');
      expect(SyncPillStyle.of(SyncPillState.checking).label, 'Checking…');
      expect(SyncPillStyle.of(SyncPillState.pairing).label, 'Pairing...');
      expect(SyncPillStyle.of(SyncPillState.idle).label, 'Tap to Pair');
      expect(SyncPillStyle.of(SyncPillState.direct).icon, AppIcons.zap);
      expect(SyncPillStyle.of(SyncPillState.relayed).icon, AppIcons.wifi);
      expect(SyncPillStyle.of(SyncPillState.checking).dotMotion, DotMotion.ping);
      expect(SyncPillStyle.of(SyncPillState.connected).dotMotion, DotMotion.pulse);
      expect(SyncPillStyle.of(SyncPillState.error).background, AppColors.rose100);
    });

    testWidgets('shows the couple name, partner presence and wires both buttons', (tester) async {
      var sync = 0;
      var lock = 0;
      await pumpHost(
        tester,
        OurHeader(
          title: 'Farhan & Sam',
          presence: const HeaderPresence.activeNow(partnerName: 'Sam'),
          syncState: SyncPillState.direct,
          onOpenSync: () => sync++,
          onLock: () => lock++,
        ),
      );
      expect(find.text('Farhan & Sam'), findsOneWidget);
      expect(find.text('Sam active now 💕'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Phone to phone ⚡'));
      await tester.tap(find.bySemanticsLabel('Lock Our Space'));
      expect(sync, 1);
      expect(lock, 1);
      expect(recordedHaptics, [HapticKind.tick, HapticKind.tick]);
    });

    testWidgets('sync error banner replaces the warning and can be dismissed', (tester) async {
      var dismissed = 0;
      var opened = 0;
      await pumpHost(
        tester,
        OurHeader(
          syncState: SyncPillState.error,
          syncErrorText: 'Could not reach your partner.',
          syncWarningText: 'Hidden while there is an error',
          onDismissSyncError: () => dismissed++,
          onOpenSync: () => opened++,
        ),
      );
      expect(find.text('Could not reach your partner.'), findsOneWidget);
      expect(find.text('Hidden while there is an error'), findsNothing);
      await tester.tap(find.text('Open the Pair & Sync hub'));
      await tester.tap(find.bySemanticsLabel('Dismiss'));
      expect(opened, 1);
      expect(dismissed, 1);
    });

    testWidgets('warning banner and sync notice pill render under the row', (tester) async {
      await pumpHost(tester, const OurHeader(syncWarningText: 'Running low on space', notice: 'Synced 2 new item(s) from Sam 💕'));
      expect(find.text('Running low on space'), findsOneWidget);
      expect(find.text('Synced 2 new item(s) from Sam 💕'), findsOneWidget);
      expect(find.byType(OurNoticePill), findsOneWidget);
    });

    testWidgets('toast scope messages appear in the header for four seconds', (tester) async {
      final controller = OurToastController();
      addTearDown(controller.dispose);
      await pumpHost(tester, OurToastScope(controller: controller, child: const OurHeader()));
      controller.show('Unlock Our Space first 💕');
      await tester.pump();
      expect(find.text('Unlock Our Space first 💕'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4100));
      expect(find.text('Unlock Our Space first 💕'), findsNothing);
    });

    testWidgets('paints the status bar strip in the PWA theme colour', (tester) async {
      usePhoneSize(tester, top: 24);
      await pumpHost(tester, const OurHeader(), scaffold: false);
      final strip = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((b) => b.color == AppColors.blush100);
      expect(strip, isNotEmpty);
    });
  });

  group('OurBottomNav', () {
    const items = [
      OurNavItem(label: 'Love', icon: AppIcons.heart),
      OurNavItem(label: 'Memories', icon: AppIcons.camera),
      OurNavItem(label: 'Dates', icon: AppIcons.sparkles),
      OurNavItem(label: 'Letters', icon: AppIcons.mail),
      OurNavItem(label: 'Bucket', icon: AppIcons.checkSquare),
    ];

    testWidgets('lays the five tabs out left to right and reports taps', (tester) async {
      final selected = <int>[];
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (context, setState) => OurBottomNav(
            items: items,
            selectedIndex: selected.isEmpty ? 0 : selected.last,
            onSelect: (i) => setState(() => selected.add(i)),
          ),
        ),
        scaffold: false,
      );
      final xs = [for (final i in items) tester.getCenter(find.text(i.label)).dx];
      expect(xs, orderedEquals([...xs]..sort()));
      await tester.tap(find.text('Letters'));
      await tester.pumpAndSettle();
      expect(selected, [3]);
      expect(recordedHaptics, [HapticKind.tick]);
      final active = tester.widgetList<LucideIcon>(find.byType(LucideIcon)).firstWhere((i) => i.icon == AppIcons.mail);
      expect(active.color, AppColors.blush500);
      expect(active.fill, AppColors.blush200);
      final idle = tester.widgetList<LucideIcon>(find.byType(LucideIcon)).firstWhere((i) => i.icon == AppIcons.heart);
      expect(idle.color, AppColors.slate400);
      expect(idle.fill, isNull);
    });

    testWidgets('height follows the web padding plus the safe area', (tester) async {
      usePhoneSize(tester, bottom: 16);
      await pumpHost(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: OurBottomNav(items: items, selectedIndex: 0, onSelect: (_) {}),
        ),
        scaffold: false,
      );
      expect(tester.getSize(find.byType(OurBottomNav)).height, OurBottomNav.heightFor(16));
      expect(OurBottomNav.heightFor(0), 62);
    });
  });
}
