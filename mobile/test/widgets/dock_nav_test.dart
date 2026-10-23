import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import 'harness.dart';

const items = [
  SkyDockItem(label: 'Sky', icon: SkyIcons.star),
  SkyDockItem(label: 'Letters', icon: SkyIcons.letter),
  SkyDockItem(label: 'Memories', icon: SkyIcons.photo),
  SkyDockItem(label: 'Us', icon: SkyIcons.us),
];

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Widget dockHost({required SkyTokens tokens, required Widget child, double width = 358, bool animations = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(tokens),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
      child: app!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

class _DockDemo extends StatefulWidget {
  const _DockDemo({required this.onLove, required this.selected});

  final VoidCallback onLove;
  final List<int> selected;

  @override
  State<_DockDemo> createState() => _DockDemoState();
}

class _DockDemoState extends State<_DockDemo> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return SkyDock(
      items: items,
      selectedIndex: _index,
      onLove: widget.onLove,
      onSelect: (i) {
        widget.selected.add(i);
        setState(() => _index = i);
      },
    );
  }
}

void main() {
  setUp(recordHaptics);

  testWidgets('every tab answers a tap anywhere across the full height of the pill', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      dockHost(
        tokens: SkyTokens.night,
        child: _DockDemo(onLove: () {}, selected: selected),
      ),
    );
    final pill = tester.getRect(find.byType(SkyDock));
    final top = pill.bottom - SkySizes.dockHeight + 4;
    final bottom = pill.bottom - 4;
    for (final index in [1, 2, 3, 0]) {
      final x = tester.getCenter(labelled(items[index].label)).dx;
      await tester.tapAt(Offset(x, index.isEven ? top : bottom));
      await tester.pumpAndSettle();
      expect(selected.last, index);
    }
    final slot = tester.getSize(labelled(items[1].label));
    expect(slot.height, greaterThanOrEqualTo(44));
  });

  testWidgets('lays the four tabs out around the love heart and reports taps', (tester) async {
    final selected = <int>[];
    var love = 0;
    await tester.pumpWidget(
      dockHost(
        tokens: SkyTokens.night,
        child: _DockDemo(onLove: () => love++, selected: selected),
      ),
    );
    final xs = [for (final i in items) tester.getCenter(find.text(i.label)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    final heart = tester.getCenter(labelled('Send love')).dx;
    expect(heart, greaterThan(xs[1]));
    expect(heart, lessThan(xs[2]));

    await tester.tap(find.text('Letters'));
    await tester.pumpAndSettle();
    expect(selected, [1]);
    expect(recordedHaptics, [HapticKind.tick]);

    await tester.tap(labelled('Send love'));
    expect(love, 1);
  });

  testWidgets('the active item is a pill: gold at night, indigo by day', (tester) async {
    for (final tokens in [SkyTokens.night, SkyTokens.day]) {
      await tester.pumpWidget(
        dockHost(
          tokens: tokens,
          child: SkyDock(items: items, selectedIndex: 2, onSelect: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final pill = tester.widget<Container>(
        find.ancestor(of: find.text('Memories'), matching: find.byType(Container)).first,
      );
      expect((pill.decoration! as BoxDecoration).color, tokens.activeBg);
      final label = tester.widget<Text>(find.text('Memories'));
      expect(label.style?.color, tokens.activeFg);
      final idle = tester.widget<Text>(find.text('Sky'));
      expect(idle.style?.color, tokens.dockIcon);
    }
    expect(SkyTokens.night.activeBg, const Color(0xFFFFD98A));
    expect(SkyTokens.day.activeBg, const Color(0xFF2B2A6B));
  });

  testWidgets('selected tab is announced as selected', (tester) async {
    await tester.pumpWidget(
      dockHost(
        tokens: SkyTokens.night,
        child: SkyDock(items: items, selectedIndex: 3, onSelect: (_) {}),
      ),
    );
    final semantics = tester.widget<Semantics>(labelled('Us'));
    expect(semantics.properties.selected, isTrue);
    expect(tester.widget<Semantics>(labelled('Sky')).properties.selected, isFalse);
  });

  testWidgets('fits a narrow phone for every selection and while switching', (tester) async {
    tester.view.physicalSize = const Size(960, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (var i = 0; i < items.length; i++) {
      await tester.pumpWidget(
        dockHost(
          tokens: SkyTokens.night,
          width: 288,
          animations: true,
          child: SkyDock(items: items, selectedIndex: i, onSelect: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(find.byType(SkyDock)).height, SkyDock.height);
  });

  testWidgets('switching animates the pill when motion is allowed', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      dockHost(
        tokens: SkyTokens.day,
        animations: true,
        child: _DockDemo(onLove: () {}, selected: selected),
      ),
    );
    await tester.tap(find.text('Us'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(AnimatedSize), findsWidgets);
    for (final size in tester.widgetList<AnimatedSize>(find.byType(AnimatedSize))) {
      expect(size.clipBehavior, Clip.none);
    }
    await tester.pumpAndSettle();
    expect(selected, [3]);
    expect(tester.takeException(), isNull);
  });

  test('dock clearance keeps pages above the dock and the safe area', () {
    expect(SkySizes.dockOffset(0), SkySizes.dockBottom);
    expect(SkySizes.dockOffset(34), 44);
    expect(SkySizes.dockClearance(0), SkySizes.dockBottom + SkySizes.dockHeight + 18);
    expect(SkyDock.height, SkySizes.dockHeight + SkySizes.dockLoveLift);
  });
}
