import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';
import 'package:our_space_mobile/presentation/widgets/our_feedback.dart';
import 'package:our_space_mobile/presentation/widgets/our_page.dart';

import 'harness.dart';

Widget _fakePage(BuildContext context, SkyTab tab) {
  return OurPage(children: [Text('page:${tab.id}'), const SizedBox(height: 2000)]);
}

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Finder inDock(String text) => find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text(text));

void main() {
  setUp(recordHaptics);

  test('tabs follow the design order, labels and icons', () {
    expect(SkyShell.tabs.map((t) => t.id), ['sky', 'letters', 'memories', 'us']);
    expect(SkyShell.tabs.map((t) => t.label), ['Sky', 'Letters', 'Memories', 'Us']);
    expect(SkyShell.tabs.map((t) => t.icon), [SkyIcons.star, SkyIcons.letter, SkyIcons.photo, SkyIcons.us]);
    expect(SkyTab.letters.dockItem.label, 'Letters');
  });

  testWidgets('the shell shows the dock and switches pages on tap', (tester) async {
    usePhoneSize(tester);
    final changes = <SkyTab>[];
    await pumpHost(tester, SkyShell(pageBuilder: _fakePage, onTabChanged: changes.add), scaffold: false);
    expect(find.byKey(ShellKeys.dock), findsOneWidget);
    expect(find.text('page:sky'), findsOneWidget);
    await tester.tap(inDock('Memories'));
    await tester.pumpAndSettle();
    expect(find.text('page:memories'), findsOneWidget);
    expect(find.text('page:sky'), findsNothing);
    expect(changes, [SkyTab.memories]);
    expect(recordedHaptics, [HapticKind.tick]);
    await tester.tap(inDock('Memories'));
    await tester.pumpAndSettle();
    expect(changes, [SkyTab.memories]);
  });

  testWidgets('tab changes fade through when motion is allowed', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, SkyShell(pageBuilder: _fakePage), scaffold: false, animations: true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(inDock('Letters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('page:sky'), findsOneWidget);
    expect(find.text('page:letters'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('page:sky'), findsNothing);
    expect(find.text('page:letters'), findsOneWidget);
  });

  testWidgets('with reduced motion the page swaps at once', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, SkyShell(pageBuilder: _fakePage), scaffold: false);
    await tester.tap(inDock('Us'));
    await tester.pump();
    expect(find.text('page:us'), findsOneWidget);
    expect(find.text('page:sky'), findsNothing);
  });

  testWidgets('pages get the dock clearance as bottom padding', (tester) async {
    usePhoneSize(tester, top: 24, bottom: 16);
    late double bottom;
    late double top;
    await pumpHost(
      tester,
      SkyShell(
        pageBuilder: (context, tab) {
          bottom = MediaQuery.paddingOf(context).bottom;
          top = MediaQuery.paddingOf(context).top;
          return const SizedBox.expand();
        },
      ),
      scaffold: false,
    );
    expect(bottom, SkySizes.dockClearance(16));
    expect(top, 24);
    final dock = tester.getRect(find.byKey(ShellKeys.dock));
    expect(844 - dock.bottom, closeTo(SkySizes.dockOffset(16), 0.5));
    expect(dock.height, SkyDock.height);
  });

  testWidgets('the love heart and the avatar reach the shell callbacks', (tester) async {
    usePhoneSize(tester);
    var love = 0;
    var settings = 0;
    await pumpHost(
      tester,
      SkyShell(
        pageBuilder: (context, tab) => const SafeArea(
          child: Align(alignment: Alignment.topRight, child: ShellAvatar()),
        ),
        myName: 'Sam',
        onOpenLove: () => love++,
        onOpenSettings: () => settings++,
      ),
      scaffold: false,
    );
    await tester.tap(labelled(ShellCopy.sendLove));
    await tester.tap(find.byKey(ShellKeys.avatar));
    expect(love, 1);
    expect(settings, 1);
    expect(find.descendant(of: find.byKey(ShellKeys.avatar), matching: find.text('S')), findsOneWidget);
  });

  testWidgets('lock falls back to ShellActions when no direct callback is given', (tester) async {
    usePhoneSize(tester);
    var locked = 0;
    await pumpHost(
      tester,
      ShellActions(
        onLock: () => locked++,
        child: SkyShell(
          pageBuilder: (context, tab) =>
              TextButton(onPressed: SkyShellScope.of(context).lock, child: const Text('lock it')),
        ),
      ),
      scaffold: false,
    );
    await tester.tap(find.text('lock it'));
    expect(locked, 1);
  });

  testWidgets('pages can switch tabs through the shell scope', (tester) async {
    usePhoneSize(tester);
    await pumpHost(
      tester,
      SkyShell(
        pageBuilder: (context, tab) => TextButton(
          onPressed: () => SkyShellScope.of(context).selectTab(SkyTab.us),
          child: Text('on:${SkyShellScope.of(context).tab.id}'),
        ),
      ),
      scaffold: false,
    );
    await tester.tap(find.text('on:sky'));
    await tester.pump();
    expect(find.text('on:us'), findsOneWidget);
  });

  testWidgets('toasts show in the shell notices without emoji and clear after four seconds', (tester) async {
    usePhoneSize(tester);
    await pumpHost(tester, SkyShell(pageBuilder: _fakePage), scaffold: false);
    OurToast.show(tester.element(find.text('page:sky')), 'Could not send that just now 💕');
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(ShellKeys.notices), matching: find.text('Could not send that just now')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Could not send that just now'), findsNothing);
  });

  testWidgets('an error notice can be dismissed or open settings, and replaces the warning', (tester) async {
    usePhoneSize(tester);
    var dismissed = 0;
    var opened = 0;
    await pumpHost(
      tester,
      SkyShell(
        pageBuilder: _fakePage,
        onOpenSettings: () => opened++,
        status: ShellStatus(
          errorText: 'We could not reach Alex just now.',
          onDismissError: () => dismissed++,
          warningText: 'Hidden while there is an error',
        ),
      ),
      scaffold: false,
    );
    expect(find.text('We could not reach Alex just now.'), findsOneWidget);
    expect(find.text('Hidden while there is an error'), findsNothing);
    await tester.tap(find.text(ShellCopy.openSettings));
    await tester.tap(labelled(ShellCopy.dismiss));
    expect(opened, 1);
    expect(dismissed, 1);
  });

  testWidgets('a warning shows on its own when there is no error', (tester) async {
    usePhoneSize(tester);
    await pumpHost(
      tester,
      SkyShell(
        pageBuilder: _fakePage,
        status: const ShellStatus(warningText: 'Running low on space'),
      ),
      scaffold: false,
    );
    expect(
      find.descendant(of: find.byKey(ShellKeys.notices), matching: find.text('Running low on space')),
      findsOneWidget,
    );
  });

  testWidgets('OurCenteredPage centres short content like min-h-screen justify-center', (tester) async {
    usePhoneSize(tester, top: 0, bottom: 0);
    await pumpHost(
      tester,
      const OurScaffold(
        particles: false,
        body: OurCenteredPage(child: SizedBox(width: 100, height: 100, child: Text('lock'))),
      ),
      scaffold: false,
    );
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
      const OurPage(
        children: [
          SizedBox(height: 10, child: Text('a')),
          SizedBox(height: 10, child: Text('b')),
        ],
      ),
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
