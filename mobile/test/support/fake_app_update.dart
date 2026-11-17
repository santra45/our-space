import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:our_space_mobile/core/engine/p2p/app_update_link.dart';
import 'package:path/path.dart' as p;

import '../p2p/support/fake_clock.dart';

Uint8List randomApk(int size, {int seed = 7}) {
  final random = math.Random(seed);
  return Uint8List.fromList(List<int>.generate(size, (_) => random.nextInt(256)));
}

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

class FakeUpdatePlatform implements AppUpdatePlatform {
  FakeUpdatePlatform({required this.code, required this.folder, this.apk, this.allowed = true});

  int code;
  String folder;
  String? apk;
  bool allowed;
  bool opens = true;
  int allowAsks = 0;
  final List<String> installs = [];
  final List<Uint8List> installedBytes = [];

  @override
  Future<InstalledApp?> installed() async => InstalledApp(code: code, name: '1.0.$code', folder: folder, apk: apk);

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> allowInstalls() async {
    allowAsks++;
  }

  @override
  Future<bool> install(String path) async {
    installs.add(path);
    installedBytes.add(await File(path).readAsBytes());
    return opens;
  }
}

class FakeUpdateWire {
  FakeUpdateWire() {
    a = FakeUpdateTransport(this, 'a');
    b = FakeUpdateTransport(this, 'b');
    a.other = b;
    b.other = a;
  }

  late final FakeUpdateTransport a;
  late final FakeUpdateTransport b;
  bool connected = false;

  void connect() {
    connected = true;
    a.readinessChanged();
    b.readinessChanged();
  }

  void drop() {
    connected = false;
    a.readinessChanged();
    b.readinessChanged();
  }
}

class FakeUpdateTransport implements AppUpdateTransport {
  FakeUpdateTransport(this.wire, this.name);

  final FakeUpdateWire wire;
  final String name;
  late final FakeUpdateTransport other;
  final List<Map<String, Object?>> sent = [];
  final List<int> pieceIndexes = [];
  void Function(int index)? afterPiece;
  Uint8List Function(int index, Uint8List piece)? tamper;
  void Function()? _onReadiness;
  void Function(Object? event)? _onEvent;
  void Function(Uint8List piece)? _onPiece;

  bool get attached => _onEvent != null;

  @override
  bool get ready => wire.connected;

  @override
  void attach({
    required void Function() onReadiness,
    required void Function(Object? event) onEvent,
    required void Function(Uint8List piece) onPiece,
  }) {
    _onReadiness = onReadiness;
    _onEvent = onEvent;
    _onPiece = onPiece;
  }

  @override
  void detach() {
    _onReadiness = null;
    _onEvent = null;
    _onPiece = null;
  }

  void readinessChanged() => _onReadiness?.call();

  void receive(Object? event) => _onEvent?.call(event);

  @override
  Future<bool> send(Map<String, Object?> event) async {
    if (!ready) return false;
    sent.add(event);
    final copy = jsonDecode(jsonEncode(event));
    Timer.run(() {
      if (wire.connected) other._onEvent?.call(copy);
    });
    return true;
  }

  @override
  Future<bool> sendPiece(Uint8List piece) async {
    if (!ready) return false;
    final index = ByteData.sublistView(piece, 0, appUpdatePieceHeaderBytes).getUint32(4);
    pieceIndexes.add(index);
    var copy = Uint8List.fromList(piece);
    final change = tamper;
    if (change != null) copy = change(index, copy);
    Timer.run(() {
      if (wire.connected) other._onPiece?.call(copy);
    });
    afterPiece?.call(index);
    return true;
  }

  List<Map<String, Object?>> sentOf(String kind) => [for (final e in sent) if (e['k'] == kind) e];
}

class UpdatePhone {
  UpdatePhone._(this.platform, this.link, this.transport, this.folder);

  static UpdatePhone open({
    required FakeUpdateTransport transport,
    required int code,
    required Directory root,
    required String name,
    Uint8List? apkBytes,
    String? apkPath,
    FakePeerClock? clock,
  }) {
    final folder = Directory(p.join(root.path, name, 'app-update'));
    String? apk = apkPath;
    if (apkBytes != null) {
      final file = File(p.join(root.path, name, 'base.apk'))..createSync(recursive: true);
      file.writeAsBytesSync(apkBytes);
      apk = file.path;
    }
    final platform = FakeUpdatePlatform(code: code, folder: folder.path, apk: apk);
    final link = AppUpdateLink(transport: transport, platform: platform, clock: clock ?? FakePeerClock());
    return UpdatePhone._(platform, link, transport, folder);
  }

  final FakeUpdatePlatform platform;
  final AppUpdateLink link;
  final FakeUpdateTransport transport;
  final Directory folder;

  List<String> get files => folder.existsSync()
      ? (folder.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()..sort())
      : const [];
}
