import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';

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

  testWidgets('the join request asks warmly, shows the phone code and resolves both ways', (tester) async {
    final answers = <bool>[];
    await pumpHost(
      tester,
      _Launcher((context) async => answers.add(await showJoinRequestDialog(context, peerId: 'our-space-abc123', fromLink: true))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(JoinRequestCopy.title), findsOneWidget);
    expect(find.text(JoinRequestCopy.fromLink), findsOneWidget);
    expect(find.text('our-space-abc123'), findsOneWidget);
    expect(find.text(JoinRequestCopy.caution), findsOneWidget);
    await tester.tap(find.text(JoinRequestCopy.connect));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(JoinRequestCopy.notNow));
    await tester.pumpAndSettle();
    expect(answers, [true, false]);
    for (final copy in [JoinRequestCopy.title, JoinRequestCopy.fromLink, JoinRequestCopy.saved, JoinRequestCopy.caution]) {
      expect(copy.toLowerCase(), isNot(contains('device')));
    }
  });
}
