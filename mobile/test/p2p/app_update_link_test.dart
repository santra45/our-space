import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/app_update_link.dart';
import 'package:path/path.dart' as p;

import '../support/fake_app_update.dart';
import 'support/engine_harness.dart';
import 'support/fake_clock.dart';

const int newer = 2450;
const int older = 2449;

int piecesFor(int size) => (size + appUpdatePieceBytes - 1) ~/ appUpdatePieceBytes;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('our_space_update_'));

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the newer phone is offered to the older one once they link, never the other way or between equals', () async {
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes + 10);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers', apkBytes: apk);
    await his.link.loaded;
    await hers.link.loaded;
    expect(his.link.available && hers.link.available, isTrue);
    expect(hers.link.stage, AppUpdateStage.none);
    expect(hers.link.visible, isFalse);

    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');
    expect(hers.link.partnerCode, newer);
    expect(his.link.partnerCode, older);
    expect(his.link.stage, AppUpdateStage.none);
    expect(hers.link.visible, isTrue);
    expect(wire.a.sentOf('hello').single, {'k': 'hello', 'code': newer, 'serves': true});
    expect(wire.b.sentOf('hello').single, {'k': 'hello', 'code': older, 'serves': true});
    expect(wire.a.pieceIndexes, isEmpty);

    final twin = FakeUpdateWire();
    final one = UpdatePhone.open(transport: twin.a, code: newer, root: root, name: 'one', apkBytes: apk);
    final two = UpdatePhone.open(transport: twin.b, code: newer, root: root, name: 'two', apkBytes: apk);
    await one.link.loaded;
    await two.link.loaded;
    twin.connect();
    await waitFor(() => one.link.partnerCode == newer && two.link.partnerCode == newer, reason: 'the hellos');
    expect(one.link.stage, AppUpdateStage.none);
    expect(two.link.stage, AppUpdateStage.none);

    final quiet = FakeUpdateWire();
    final cannot = UpdatePhone.open(transport: quiet.a, code: newer, root: root, name: 'cannot');
    final waiting = UpdatePhone.open(transport: quiet.b, code: older, root: root, name: 'waiting', apkBytes: apk);
    await cannot.link.loaded;
    await waiting.link.loaded;
    quiet.connect();
    await waitFor(() => waiting.link.partnerCode == newer, reason: 'the hello from a phone that cannot share');
    expect(waiting.link.stage, AppUpdateStage.none);
    expect(await waiting.link.fetch(), isFalse);

    for (final phone in [his, hers, one, two, cannot, waiting]) {
      phone.link.dispose();
    }
  });

  test('the update comes over in pieces, is checked, and opens the installer once the phone may install', () async {
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 5 + 1234, seed: 11);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');

    var sawSharing = false;
    his.link.addListener(() => sawSharing = sawSharing || his.link.sharing);
    expect(await hers.link.fetch(), isTrue);
    expect(hers.link.stage, AppUpdateStage.fetching);
    await waitFor(() => hers.link.stage == AppUpdateStage.ready, reason: 'the whole update');

    expect(hers.link.progress, 1);
    expect(hers.link.readyCode, newer);
    final sha = sha256Hex(apk);
    expect(hers.files, ['$newer-$sha.apk']);
    expect(File(p.join(hers.folder.path, '$newer-$sha.apk')).readAsBytesSync(), apk);
    expect(wire.b.sentOf('want').single, {'k': 'want', 'code': newer});
    expect(wire.a.sentOf('offer').single, {
      'k': 'offer',
      'code': newer,
      'size': apk.length,
      'sha256': sha,
      'piece': appUpdatePieceBytes,
    });
    expect(wire.a.pieceIndexes, List<int>.generate(piecesFor(apk.length), (i) => i));
    for (final ask in wire.b.sentOf('get')) {
      expect(ask['count'] as int, lessThanOrEqualTo(appUpdateWindow));
    }
    expect(sawSharing, isTrue);
    expect(his.link.shareProgress, 1);
    expect(his.link.sharing, isFalse);

    hers.platform.allowed = false;
    expect(await hers.link.install(), isFalse);
    expect(hers.link.stage, AppUpdateStage.needsPermission);
    expect(hers.platform.allowAsks, 1);
    expect(hers.platform.installs, isEmpty);

    hers.link.onForeground();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hers.link.stage, AppUpdateStage.needsPermission);
    expect(hers.platform.installs, isEmpty);

    hers.platform.allowed = true;
    hers.link.onForeground();
    await waitFor(
      () => hers.link.stage == AppUpdateStage.installing && hers.platform.installedBytes.isNotEmpty,
      reason: 'the installer',
    );
    expect(hers.platform.installs.single, p.join(hers.folder.path, '$newer-$sha.apk'));
    expect(hers.platform.installedBytes.single, apk);

    hers.link.onForeground();
    expect(hers.link.stage, AppUpdateStage.ready);
    expect(await hers.link.install(), isTrue);
    expect(hers.platform.installs, hasLength(2));

    hers.platform.opens = false;
    hers.link.onForeground();
    expect(await hers.link.install(), isFalse);
    expect(hers.link.stage, AppUpdateStage.ready);

    his.link.dispose();
    hers.link.dispose();
  });

  test('a dropped line pauses the update and it carries on from the piece it stopped at', () async {
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 20 + 77, seed: 23);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');

    wire.a.afterPiece = (index) {
      if (index == 9) wire.drop();
    };
    await hers.link.fetch();
    await waitFor(() => !wire.connected, reason: 'the line to drop');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(hers.link.stage, AppUpdateStage.fetching);
    expect(hers.link.linked, isFalse);
    final heldBefore = (hers.link.progress * piecesFor(apk.length)).round();
    expect(heldBefore, inInclusiveRange(1, 10));
    expect(hers.link.progress, lessThan(1));
    final sentBefore = wire.a.pieceIndexes.length;

    wire.a.afterPiece = null;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.ready, reason: 'the rest of the update');
    final afterDrop = wire.a.pieceIndexes.sublist(sentBefore);
    expect(afterDrop.first, heldBefore);
    expect(afterDrop, List<int>.generate(piecesFor(apk.length) - heldBefore, (i) => heldBefore + i));
    expect(wire.b.sentOf('want'), hasLength(1));
    expect(File(p.join(hers.folder.path, '$newer-${sha256Hex(apk)}.apk')).readAsBytesSync(), apk);

    his.link.dispose();
    hers.link.dispose();
  });

  test('an update half fetched when the app closed picks up from what was already saved', () async {
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 12 + 5, seed: 31);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    var hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');

    wire.a.afterPiece = (index) {
      if (index == 6) wire.drop();
    };
    await hers.link.fetch();
    await waitFor(() => !wire.connected, reason: 'the line to drop');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final held = (hers.link.progress * piecesFor(apk.length)).round();
    expect(held, greaterThan(0));
    hers.link.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final sha = sha256Hex(apk);
    expect(hers.files, ['$newer-$sha.part']);
    expect(File(p.join(hers.folder.path, '$newer-$sha.part')).lengthSync(), held * appUpdatePieceBytes);

    hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await hers.link.loaded;
    wire.a.afterPiece = null;
    final sentBefore = wire.a.pieceIndexes.length;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer again');
    await hers.link.fetch();
    await waitFor(() => hers.link.stage == AppUpdateStage.ready, reason: 'the rest');
    expect(wire.a.pieceIndexes.sublist(sentBefore).first, held);
    expect(hers.files, ['$newer-$sha.apk']);
    expect(File(p.join(hers.folder.path, '$newer-$sha.apk')).readAsBytesSync(), apk);

    his.link.dispose();
    hers.link.dispose();
  });

  test('pieces that do not add up are thrown away, and trying again brings the real thing', () async {
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 4 + 99, seed: 41);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');

    wire.a.tamper = (index, piece) {
      if (index == 2) piece[appUpdatePieceHeaderBytes + 100] ^= 0xff;
      return piece;
    };
    await hers.link.fetch();
    await waitFor(() => hers.link.stage == AppUpdateStage.failed, reason: 'the check to fail');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hers.files, isEmpty);
    expect(hers.link.readyCode, isNull);
    expect(await hers.link.install(), isFalse);
    expect(hers.platform.installs, isEmpty);

    wire.a.tamper = null;
    expect(await hers.link.fetch(), isTrue);
    await waitFor(() => hers.link.stage == AppUpdateStage.ready, reason: 'the second try');
    expect(File(p.join(hers.folder.path, '$newer-${sha256Hex(apk)}.apk')).readAsBytesSync(), apk);

    his.link.dispose();
    hers.link.dispose();
  });

  test('old leftovers are tidied on start, and a checked update waits for her even with him away', () async {
    final folder = Directory(p.join(root.path, 'hers', 'app-update'))..createSync(recursive: true);
    final shaA = 'a' * 64;
    final shaB = 'b' * 64;
    final shaC = 'c' * 64;
    for (final name in ['$older-$shaA.apk', '2440-$shaA.part', '$newer-$shaB.apk', '2451-$shaC.apk', '2452-$shaA.part', 'notes.txt']) {
      File(p.join(folder.path, name)).writeAsBytesSync([1, 2, 3]);
    }
    final wire = FakeUpdateWire();
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await hers.link.loaded;

    expect(hers.files, ['2451-$shaC.apk', '2452-$shaA.part', 'notes.txt']);
    expect(hers.link.stage, AppUpdateStage.ready);
    expect(hers.link.readyCode, 2451);
    expect(hers.link.linked, isFalse);
    expect(await hers.link.install(), isTrue);
    expect(hers.platform.installs.single, p.join(folder.path, '2451-$shaC.apk'));
    hers.link.dispose();
  });

  test('a phone that cannot share says so, and requests that do not fit are ignored', () async {
    final wire = FakeUpdateWire();
    final his = UpdatePhone.open(
      transport: wire.a,
      code: newer,
      root: root,
      name: 'his',
      apkPath: p.join(root.path, 'missing', 'base.apk'),
    );
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers');
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');
    await hers.link.fetch();
    await waitFor(() => hers.link.stage == AppUpdateStage.failed, reason: 'the refusal');
    expect(wire.a.sentOf('none').single, {'k': 'none', 'code': newer});
    expect(wire.a.pieceIndexes, isEmpty);
    expect(await hers.link.fetch(), isFalse);
    his.link.dispose();
    hers.link.dispose();

    final other = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 2, seed: 53);
    final sharer = UpdatePhone.open(transport: other.a, code: newer, root: root, name: 'sharer', apkBytes: apk);
    final asker = UpdatePhone.open(transport: other.b, code: older, root: root, name: 'asker');
    await sharer.link.loaded;
    await asker.link.loaded;
    other.connect();
    await waitFor(() => asker.link.stage == AppUpdateStage.available, reason: 'the offer');
    for (final odd in <Object?>[
      {'k': 'get', 'code': older, 'from': 0, 'count': 2},
      {'k': 'get', 'code': newer, 'from': -1, 'count': 2},
      {'k': 'get', 'code': newer, 'from': 0, 'count': 0},
      {'k': 'get', 'code': newer, 'from': 0, 'count': appUpdateWindow * 2 + 1},
      {'k': 'get', 'code': '$newer', 'from': 0, 'count': 2},
      {'k': 'want', 'code': '$newer'},
      {'k': 'hello', 'code': -4, 'serves': true},
      {'k': 'offer', 'code': newer, 'size': 10, 'sha256': 'nope', 'piece': appUpdatePieceBytes},
      'text',
      null,
    ]) {
      sharer.transport.receive(odd);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(other.a.pieceIndexes, isEmpty);
    expect(other.a.sentOf('offer'), isEmpty);
    expect(sharer.link.partnerCode, older);
    expect(sharer.link.stage, AppUpdateStage.none);

    sharer.transport.receive({'k': 'want', 'code': older});
    await waitFor(() => other.a.sentOf('none').isNotEmpty, reason: 'the polite no');
    expect(other.a.sentOf('none').single, {'k': 'none', 'code': older});
    sharer.link.dispose();
    asker.link.dispose();
  });

  test('a stalled update asks again from where it is, and a newer one from him replaces the half fetched one', () async {
    final clock = FakePeerClock();
    final wire = FakeUpdateWire();
    final apk = randomApk(appUpdatePieceBytes * 6, seed: 61);
    final his = UpdatePhone.open(transport: wire.a, code: newer, root: root, name: 'his', apkBytes: apk);
    final hers = UpdatePhone.open(transport: wire.b, code: older, root: root, name: 'hers', clock: clock);
    await his.link.loaded;
    await hers.link.loaded;
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the offer');

    final lost = <int>{};
    wire.a.tamper = (index, piece) {
      if (index >= 3) lost.add(index);
      return index >= 3 ? Uint8List(appUpdatePieceHeaderBytes + 1) : piece;
    };
    await hers.link.fetch();
    await waitFor(() => lost.length == 3, reason: 'the lost pieces');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(hers.link.stage, AppUpdateStage.fetching);
    final asksBefore = wire.b.sentOf('get').length;

    wire.a.tamper = null;
    clock.advance(const Duration(milliseconds: appUpdateStallMs + appUpdateTickMs));
    await waitFor(() => hers.link.stage == AppUpdateStage.ready, reason: 'the second ask');
    expect(wire.b.sentOf('get').sublist(asksBefore).first['from'], 3);
    expect(File(p.join(hers.folder.path, '$newer-${sha256Hex(apk)}.apk')).readAsBytesSync(), apk);

    final next = randomApk(appUpdatePieceBytes * 6, seed: 62);
    File(his.platform.apk!).writeAsBytesSync(next);
    his.link.dispose();
    final later = UpdatePhone.open(transport: wire.a, code: newer + 1, root: root, name: 'his', apkPath: his.platform.apk);
    await later.link.loaded;
    wire.drop();
    wire.connect();
    await waitFor(() => hers.link.stage == AppUpdateStage.available, reason: 'the newer offer');
    expect(hers.link.partnerCode, newer + 1);
    expect(hers.link.readyCode, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hers.files, isEmpty);

    later.link.dispose();
    hers.link.dispose();
  });
}
