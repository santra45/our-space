import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_sky_together.dart';
import '../../../support/harness.dart';

class PresenceLine extends StatelessWidget {
  const PresenceLine({super.key});

  @override
  Widget build(BuildContext context) {
    final link = SkyTogetherScope.maybeOf(context);
    if (link == null) return const Text('alone');
    return ListenableBuilder(listenable: link, builder: (context, _) => Text(link.partnerHere ? 'here' : 'away'));
  }
}

Widget framed(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('a widget test can hold one phone in the tree and drive the other phone from the test', (tester) async {
    final pair = FakeSkyPair(connected: false);
    final drawings = <SkyDrawingService?>[];
    await tester.pumpWidget(
      framed(
        SkyTogetherScope(
          link: pair.a,
          child: Builder(
            builder: (context) {
              drawings.add(SkyTogetherScope.drawingsOf(context));
              return const PresenceLine();
            },
          ),
        ),
      ),
    );
    expect(find.text('away'), findsOneWidget);
    expect(drawings.last, isNull);

    pair.connect();
    pair.settle();
    await tester.pump();
    expect(find.text('here'), findsOneWidget);

    final heard = <SkyTogetherEvent>[];
    final sub = pair.a.events.listen(heard.add);
    final press = pair.b.sendHold(down: true);
    pair.flush();
    await tester.pump();
    expect(heard.whereType<SkyHoldEvent>().single, press);
    expect(press.at, pair.b.sharedNow());

    pair.b.setForeground(false);
    pair.flush();
    await tester.pump();
    expect(find.text('away'), findsOneWidget);

    unawaited(sub.cancel());
    pair.dispose();
  });

  testWidgets('without a scope the link and the drawings come from the space, and with neither there is none',
      (tester) async {
    await tester.pumpWidget(framed(const PresenceLine()));
    expect(find.text('alone'), findsOneWidget);

    final space = (await tester.runAsync(() {
      final dir = Directory.systemTemp.createTempSync('our_space_scope_');
      return OurSpace.open(
        databaseFactory: testDatabaseFactory(),
        databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
        useEnvironmentMailbox: false,
        autoSync: false,
      );
    }))!;
    SkyTogetherLink? link;
    SkyDrawingService? drawings;
    await tester.pumpWidget(
      framed(
        Provider<OurSpace>.value(
          value: space,
          child: Builder(
            builder: (context) {
              link = SkyTogetherScope.maybeOf(context);
              drawings = SkyTogetherScope.drawingsOf(context);
              return const PresenceLine();
            },
          ),
        ),
      ),
    );
    expect(link, same(space.peer.skyTogether));
    expect(drawings, same(space.skyDrawings));
    expect(find.text('away'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(space.close);
  });
}
