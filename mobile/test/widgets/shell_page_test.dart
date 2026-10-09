import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/our_bottom_nav.dart';
import 'package:our_space_mobile/presentation/widgets/our_feedback.dart';
import 'package:our_space_mobile/presentation/widgets/our_header.dart';
import 'package:our_space_mobile/presentation/widgets/our_page.dart';

import 'harness.dart';

Widget _fakePage(BuildContext context, AppTab tab) {
  return OurPage(children: [Text('page:${tab.id}'), const SizedBox(height: 2000)]);
}

void main() {
  setUp(recordHaptics);

  test('tabs keep the web order, labels and icons', () {
    expect(AppShell.tabs.map((t) => t.id), ['countdown', 'polaroids', 'roulette', 'capsule', 'bucketlist']);
    expect(AppShell.tabs.map((t) => t.label), ['Love', 'Memories', 'Dates', 'Letters', 'Bucket']);
    expect(AppShell.tabs.map((t) => t.navItem.icon), [
      AppIcons.heart,
      AppIcons.camera,
      AppIcons.sparkles,
      AppIcons.mail,
      AppIcons.checkSquare,
    ]);
  });

  testWidgets('shell shows the header, the nav and switches pages on tap', (tester) async {
    usePhoneSize(tester);
    final changes = <AppTab>[];
    await pumpHost(
      tester,
      AppShell(pageBuilder: _fakePage, particles: false, onTabChanged: changes.add),
      scaffold: false,
    );
    expect(find.byType(OurHeader), findsOneWidget);
    expect(find.byType(OurBottomNav), findsOneWidget);
    expect(find.text('page:countdown'), findsOneWidget);
    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();
    expect(find.text('page:roulette'), findsOneWidget);
    expect(find.text('page:countdown'), findsNothing);
    expect(changes, [AppTab.roulette]);
  });

  testWidgets('tab change fades out, then in, like AnimatePresence mode wait', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, AppShell(pageBuilder: _fakePage, particles: false), scaffold: false, animations: true);
    await tester.tap(find.text('Letters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.text('page:countdown'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('page:capsule'), findsOneWidget);
    expect(find.text('page:countdown'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('page:capsule'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('pages sit below the measured header and keep the web bottom padding', (tester) async {
    usePhoneSize(tester, top: 24, bottom: 16);
    await pumpHost(tester, AppShell(pageBuilder: _fakePage, particles: false), scaffold: false);
    await tester.pump();
    final headerBottom = tester.getBottomLeft(find.byType(OurHeader)).dy;
    final textTop = tester.getTopLeft(find.text('page:countdown')).dy;
    expect(textTop, closeTo(headerBottom + 16, 0.5));
    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect((scroll.padding! as EdgeInsets).bottom, 16 + 88);
    expect((scroll.padding! as EdgeInsets).left, 16);
  });

  testWidgets('lock and sync use ShellActions when no direct callbacks are given', (tester) async {
    usePhoneSize(tester);
    var locked = 0;
    var synced = 0;
    final handle = tester.ensureSemantics();
    await pumpHost(
      tester,
      ShellActions(
        onLock: () => locked++,
        onOpenSync: () => synced++,
        child: AppShell(pageBuilder: _fakePage, particles: false),
      ),
      scaffold: false,
    );
    await tester.tap(find.bySemanticsLabel('Lock Our Space'));
    await tester.tap(find.bySemanticsLabel('Tap to Pair'));
    expect(locked, 1);
    expect(synced, 1);
    handle.dispose();
  });

  testWidgets('OurToast shows inside the shell header', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, AppShell(pageBuilder: _fakePage, particles: false), scaffold: false);
    OurToast.show(tester.element(find.text('page:countdown')), 'Could not send that just now 💕');
    await tester.pump();
    expect(
      find.descendant(of: find.byType(OurHeader), matching: find.text('Could not send that just now 💕')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Could not send that just now 💕'), findsNothing);
  });

  testWidgets('backdrop gradient scrolls with the page like the web body background', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, AppShell(pageBuilder: _fakePage, particles: false), scaffold: false);
    await tester.pump();
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<BodyGradientPainter>()
        .single;
    final before = painter.scroll.value!;
    expect(before.pixels, 0);
    expect(before.maxScrollExtent, greaterThan(1000));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(painter.scroll.value!.pixels, greaterThan(200));
    final rect = BodyGradientPainter.documentRect(const Size(390, 844), painter.scroll.value);
    expect(rect.top, -painter.scroll.value!.pixels);
    expect(rect.height, 844 + before.maxScrollExtent);
  });

  testWidgets('OurCenteredPage centres short content like min-h-screen justify-center', (tester) async {
    usePhoneSize(tester, top: 0, bottom: 0);
    await pumpHost(tester, const OurScaffold(particles: false, body: OurCenteredPage(child: SizedBox(width: 100, height: 100, child: Text('lock')))), scaffold: false);
    final center = tester.getCenter(find.text('lock'));
    expect(center.dy, closeTo(844 / 2, 1));
    expect(center.dx, closeTo(390 / 2, 1));
  });

  testWidgets('OurPage spaces children 16px apart and caps width at max-w-md', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHost(
      tester,
      const OurPage(children: [SizedBox(height: 10, child: Text('a')), SizedBox(height: 10, child: Text('b'))]),
      scaffold: false,
    );
    final a = tester.getRect(find.text('a'));
    final b = tester.getRect(find.text('b'));
    expect(b.top - a.bottom, 16);
    expect(a.width, 448);
  });

  test('spaced inserts gaps only between children', () {
    final out = spaced(const [Text('1'), Text('2'), Text('3')], 8);
    expect(out.length, 5);
    expect((out[1] as SizedBox).height, 8);
    expect(spaced(const [Text('1')], 8).length, 1);
  });

  test('body gradient keeps the web colours', () {
    final painter = BodyGradientPainter(ValueNotifier<DocumentScroll?>(null));
    expect(BodyGradientPainter.documentRect(const Size(100, 200), null), const Rect.fromLTWH(0, 0, 100, 200));
    expect(painter.scroll.value, isNull);
    expect(AppColors.blush50.toARGB32(), 0xFFFFF5F7);
  });
}
