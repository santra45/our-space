import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/route_requests.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_read_page.dart';
import 'package:provider/provider.dart';

import 'love/love_harness.dart';

void main() {
  test('routes pick their tab, and anything unknown stays where it is', () {
    expect(tabForRoute('letters/let-1'), SkyTab.letters);
    expect(tabForRoute('memories/mem-1'), SkyTab.memories);
    expect(tabForRoute('us'), SkyTab.us);
    expect(tabForRoute('us/dreams'), SkyTab.us);
    expect(tabForRoute('daily'), SkyTab.sky);
    expect(tabForRoute('love'), isNull);
    expect(tabForRoute('elsewhere'), isNull);

    final routes = RouteRequests();
    routes.open('  ');
    expect(routes.pending, isNull);
    routes.open('letters/let-1');
    expect(routes.takePrefixed('memories/'), isNull);
    expect(routes.takePrefixed('letters/'), 'let-1');
    expect(routes.pending, isNull);
    routes.dispose();
  });

  testWidgets('a tap from outside opens that very letter, and another lands on the dreams', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final written = await real(tester, () => space.letters.writeLetter(title: 'For you', content: 'Read me slowly'));
    final id = written!['id'] as String;
    await pumpNight(tester, space);

    final routes = tester.element(find.byType(HomeShell)).read<RouteRequests>();
    routes.open('letters/$id');
    await untilFound(tester, find.byType(LetterReadPage));
    expect(tester.state<SkyShellState>(find.byType(SkyShell)).tab, SkyTab.letters);
    expect(routes.pending, isNull);

    tester.state<SkyShellState>(find.byType(SkyShell)).selectTab(SkyTab.sky);
    await tester.pump();
    routes.open('us/dreams');
    await until(tester, () => tester.state<SkyShellState>(find.byType(SkyShell)).tab == SkyTab.us);
    await until(tester, () => routes.pending == null);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
