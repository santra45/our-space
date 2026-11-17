import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/app_update_link.dart' show appUpdatePieceBytes;
import 'package:path/path.dart' as p;

import '../support/fake_app_update.dart';
import 'peer_hub_test.dart' show pairedPhones;
import 'support/engine_harness.dart';
import 'support/fake_peer.dart';

void main() {
  test('his phone hands its own app to hers over the live link, and hers keeps it ready to install', () async {
    final root = Directory.systemTemp.createTempSync('our_space_update_hub_');
    final apk = randomApk(appUpdatePieceBytes * 3 + 4321, seed: 71);
    final apkFile = File(p.join(root.path, 'his', 'base.apk'))..createSync(recursive: true);
    apkFile.writeAsBytesSync(apk);
    final his = FakeUpdatePlatform(code: 2450, folder: p.join(root.path, 'his', 'app-update'), apk: apkFile.path);
    final hers = FakeUpdatePlatform(code: 2449, folder: p.join(root.path, 'hers', 'app-update'));

    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network, updatesA: his, updatesB: hers);
    final mine = a.hub.appUpdate;
    final theirs = b.hub.appUpdate;
    expect(theirs.stage, AppUpdateStage.none);

    b.hub.confirmPendingInvite();
    await waitFor(() => a.hub.isAuthorized && b.hub.isAuthorized, reason: 'pairing');
    await waitFor(() => theirs.stage == AppUpdateStage.available, reason: 'her phone to hear of the newer app');
    expect(theirs.partnerCode, 2450);
    expect(mine.partnerCode, 2449);
    expect(mine.stage, AppUpdateStage.none);

    expect(await theirs.fetch(), isTrue);
    await waitFor(() => theirs.stage == AppUpdateStage.ready, reason: 'the update to come over');
    final ready = File(p.join(hers.folder, '2450-${sha256Hex(apk)}.apk'));
    expect(ready.readAsBytesSync(), apk);
    expect(mine.shareProgress, 1);

    expect(await theirs.install(), isTrue);
    expect(hers.installs.single, ready.path);
    expect(a.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);
    expect(b.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);
    expect(a.hub.isAuthorized && b.hub.isAuthorized, isTrue);

    await a.close();
    await b.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a phone with no way to update leaves the link quiet', () async {
    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network);
    b.hub.confirmPendingInvite();
    await waitFor(() => a.hub.isAuthorized && b.hub.isAuthorized, reason: 'pairing');
    await settle();
    expect(a.hub.appUpdate.available, isFalse);
    expect(b.hub.appUpdate.available, isFalse);
    expect(a.hub.appUpdate.visible || b.hub.appUpdate.visible, isFalse);
    expect(await b.hub.appUpdate.fetch(), isFalse);
    await a.close();
    await b.close();
  });
}
