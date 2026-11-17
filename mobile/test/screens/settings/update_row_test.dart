import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/app_update_link.dart' show AppUpdateTransport;
import 'package:our_space_mobile/presentation/screens/settings/widgets/update_row.dart';

import '../../widgets/harness.dart';

class _SilentTransport implements AppUpdateTransport {
  @override
  bool get ready => false;

  @override
  void attach({
    required void Function() onReadiness,
    required void Function(Object? event) onEvent,
    required void Function(Uint8List piece) onPiece,
  }) {}

  @override
  void detach() {}

  @override
  Future<bool> send(Map<String, Object?> event) async => false;

  @override
  Future<bool> sendPiece(Uint8List piece) async => false;
}

class StubUpdateLink extends AppUpdateLink {
  StubUpdateLink() : super(transport: _SilentTransport());

  AppUpdateStage shownStage = AppUpdateStage.none;
  bool shownLinked = true;
  bool shownChecking = false;
  double shownProgress = 0;
  bool shownSharing = false;
  double shownShare = 0;
  int fetches = 0;
  int installs = 0;

  void show({
    AppUpdateStage? stage,
    bool? linked,
    bool? checking,
    double? progress,
    bool? sharing,
    double? share,
  }) {
    shownStage = stage ?? shownStage;
    shownLinked = linked ?? shownLinked;
    shownChecking = checking ?? shownChecking;
    shownProgress = progress ?? shownProgress;
    shownSharing = sharing ?? shownSharing;
    shownShare = share ?? shownShare;
    notifyListeners();
  }

  @override
  AppUpdateStage get stage => shownStage;

  @override
  bool get linked => shownLinked;

  @override
  bool get checking => shownChecking;

  @override
  double get progress => shownProgress;

  @override
  bool get sharing => shownSharing;

  @override
  double get shareProgress => shownShare;

  @override
  Future<bool> fetch() async {
    fetches++;
    return true;
  }

  @override
  Future<bool> install() async {
    installs++;
    return true;
  }
}

Widget rowFor(AppUpdateLink link, String partner) =>
    ListenableBuilder(listenable: link, builder: (context, _) => UpdateRow(link: link, partner: partner));

void main() {
  test('the words stay plain, and an empty name falls back to a gentle one', () {
    expect(UpdateCopy.title('Sam'), 'A newer Our Space from Sam');
    expect(UpdateCopy.title('  '), 'A newer Our Space from your partner');
    expect(UpdateCopy.arrived(''), 'Your partner has a newer Our Space for you. It is waiting in Settings.');
    expect(UpdateCopy.arrived('sam'), 'Sam has a newer Our Space for you. It is waiting in Settings.');
    expect(UpdateCopy.coming(42), 'Coming over, 42%. Keep Our Space open.');
    expect(UpdateCopy.sharingTitle('Sam'), 'Sending Sam the newer Our Space');
    expect(updatePercent(0.999), 99);
    expect(updatePercent(1), 100);
    expect(updatePercent(-1), 0);
  });

  testWidgets('her row tells her where the update is at, and each tap does the one thing it says', (tester) async {
    final link = StubUpdateLink();
    addTearDown(link.dispose);
    await pumpHost(tester, rowFor(link, 'Sam'));
    expect(find.text(UpdateCopy.title('Sam')), findsNothing);

    link.show(stage: AppUpdateStage.available);
    await tester.pump();
    expect(find.text(UpdateCopy.title('Sam')), findsOneWidget);
    expect(find.text(UpdateCopy.tapToGet), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.fetches, 1);

    link.show(linked: false);
    await tester.pump();
    expect(find.text(UpdateCopy.openBoth), findsOneWidget);

    link.show(stage: AppUpdateStage.fetching, linked: true, progress: 0.426);
    await tester.pump();
    expect(find.text(UpdateCopy.coming(42)), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.fetches, 1);

    link.show(linked: false);
    await tester.pump();
    expect(find.text(UpdateCopy.paused(42)), findsOneWidget);

    link.show(linked: true, checking: true, progress: 1);
    await tester.pump();
    expect(find.text(UpdateCopy.checking), findsOneWidget);

    link.show(stage: AppUpdateStage.ready, checking: false);
    await tester.pump();
    expect(find.text(UpdateCopy.ready), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.installs, 1);

    link.show(stage: AppUpdateStage.needsPermission);
    await tester.pump();
    expect(find.text(UpdateCopy.allow), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.installs, 2);

    link.show(stage: AppUpdateStage.installing);
    await tester.pump();
    expect(find.text(UpdateCopy.opening), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.installs, 2);

    link.show(stage: AppUpdateStage.failed);
    await tester.pump();
    expect(find.text(UpdateCopy.failed), findsOneWidget);
    await tester.tap(find.text(UpdateCopy.title('Sam')));
    await tester.pump();
    expect(link.fetches, 2);
  });

  testWidgets('his row shows how far the update has gone to her, and disappears once it is there', (tester) async {
    final link = StubUpdateLink();
    addTearDown(link.dispose);
    await pumpHost(tester, rowFor(link, 'Alex'));

    link.show(sharing: true, share: 0.61);
    await tester.pump();
    expect(find.text(UpdateCopy.sharingTitle('Alex')), findsOneWidget);
    expect(find.text(UpdateCopy.shared(61)), findsOneWidget);

    link.show(sharing: false, share: 1);
    await tester.pump();
    expect(find.text(UpdateCopy.sharingTitle('Alex')), findsNothing);
  });
}
