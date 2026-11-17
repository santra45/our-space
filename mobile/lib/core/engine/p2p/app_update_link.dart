import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'peer_clock.dart';

const int appUpdatePieceBytes = 256 * 1024;
const int appUpdateMinPieceBytes = 16 * 1024;
const int appUpdateMaxPieceBytes = 1024 * 1024;
const int appUpdateWindow = 8;
const int appUpdateMaxBytes = 300 * 1024 * 1024;
const int appUpdateStallMs = 20000;
const int appUpdateTickMs = 5000;
const int appUpdateShareQuietMs = 30000;
const int appUpdatePieceHeaderBytes = 8;

final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
final RegExp _updateFileName = RegExp(r'^(\d+)-([0-9a-f]{64})\.(part|apk)$');

@immutable
class InstalledApp {
  const InstalledApp({required this.code, required this.name, required this.folder, this.apk});

  final int code;
  final String name;
  final String folder;
  final String? apk;
}

abstract class AppUpdatePlatform {
  Future<InstalledApp?> installed();

  Future<bool> canInstall();

  Future<void> allowInstalls();

  Future<bool> install(String path);
}

class MethodChannelAppUpdate implements AppUpdatePlatform {
  const MethodChannelAppUpdate();

  static const MethodChannel channel = MethodChannel('our_space/app_update');

  @override
  Future<InstalledApp?> installed() async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>('installed');
      if (raw == null) return null;
      final code = raw['code'];
      final name = raw['name'];
      final folder = raw['folder'];
      final apk = raw['apk'];
      if (code is! int || code <= 0 || folder is! String || folder.isEmpty) return null;
      return InstalledApp(
        code: code,
        name: name is String ? name : '',
        folder: folder,
        apk: apk is String && apk.isNotEmpty ? apk : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> canInstall() async {
    try {
      return await channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> allowInstalls() async {
    try {
      await channel.invokeMethod<Object?>('allowInstalls');
    } catch (_) {}
  }

  @override
  Future<bool> install(String path) async {
    try {
      return await channel.invokeMethod<bool>('install', path) ?? false;
    } catch (_) {
      return false;
    }
  }
}

abstract class AppUpdateTransport {
  bool get ready;

  void attach({
    required void Function() onReadiness,
    required void Function(Object? event) onEvent,
    required void Function(Uint8List piece) onPiece,
  });

  void detach();

  Future<bool> send(Map<String, Object?> event);

  Future<bool> sendPiece(Uint8List piece);
}

enum AppUpdateStage { none, available, fetching, ready, needsPermission, installing, failed }

class _Offer {
  const _Offer({required this.code, required this.size, required this.sha, required this.piece});

  final int code;
  final int size;
  final String sha;
  final int piece;

  int get total => (size + piece - 1) ~/ piece;

  int lengthOf(int index) => index == total - 1 ? size - index * piece : piece;
}

class _Serving {
  const _Serving({required this.code, required this.path, required this.size, required this.sha});

  final int code;
  final String path;
  final int size;
  final String sha;
}

class _Ask {
  const _Ask(this.from, this.count);

  final int from;
  final int count;
}

Future<String> _sha256OfFile(String path) async {
  final digest = await crypto.sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

Future<String> fileSha256(String path) => Isolate.run(() => _sha256OfFile(path));

Uint8List framePiece(int code, int index, List<int> data) {
  final piece = Uint8List(appUpdatePieceHeaderBytes + data.length);
  ByteData.sublistView(piece, 0, appUpdatePieceHeaderBytes)
    ..setUint32(0, code & 0xffffffff)
    ..setUint32(4, index);
  piece.setRange(appUpdatePieceHeaderBytes, piece.length, data);
  return piece;
}

class AppUpdateLink extends ChangeNotifier {
  AppUpdateLink({
    required this._transport,
    AppUpdatePlatform? platform,
    this._clock = const SystemPeerClock(),
  }) : _platform = platform {
    if (platform == null) return;
    _transport.attach(onReadiness: _readinessChanged, onEvent: _onEvent, onPiece: _onPiece);
    _ticker = _clock.every(const Duration(milliseconds: appUpdateTickMs), _tick);
    _loading = _load();
  }

  final AppUpdateTransport _transport;
  final AppUpdatePlatform? _platform;
  final PeerClock _clock;

  Future<void> _loading = Future<void>.value();
  Timer? _ticker;
  bool _disposed = false;
  InstalledApp? _app;
  bool _wasReady = false;

  int? _partnerCode;
  bool _partnerServes = false;

  AppUpdateStage _stage = AppUpdateStage.none;
  int? _wantCode;
  _Offer? _offer;
  RandomAccessFile? _part;
  int _next = 0;
  int _requestedUpTo = 0;
  int? _lastPieceAt;
  int? _askedAt;
  Future<void> _writes = Future<void>.value();
  bool _checking = false;
  String? _readyPath;
  int? _readyCode;

  Future<_Serving?>? _serving;
  final List<_Ask> _asks = [];
  bool _sharing = false;
  int _shareGen = 0;
  int _sharedPieces = 0;
  int _shareTotal = 0;
  int? _lastShareAt;
  bool _shareShown = false;

  bool get available => _platform != null;
  Future<void> get loaded => _loading;
  AppUpdateStage get stage => _stage;
  bool get linked => _transport.ready;
  bool get checking => _checking;
  int? get myCode => _app?.code;
  int? get partnerCode => _partnerCode;
  int? get readyCode => _readyCode;

  double get progress {
    if (_stage == AppUpdateStage.ready) return 1;
    final offer = _offer;
    if (offer == null || offer.total == 0) return 0;
    return math.min(1, _next / offer.total);
  }

  bool get sharing {
    final last = _lastShareAt;
    if (last == null || _shareTotal == 0 || _sharedPieces >= _shareTotal) return false;
    return _clock.now() - last < appUpdateShareQuietMs;
  }

  double get shareProgress => _shareTotal == 0 ? 0 : math.min(1, _sharedPieces / _shareTotal);

  bool get visible => _stage != AppUpdateStage.none || sharing;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _load() async {
    final app = await _platform!.installed();
    if (_disposed || app == null) return;
    _app = app;
    await _tidy(app);
    if (_disposed) return;
    _consider();
    notifyListeners();
    _readinessChanged();
  }

  Future<void> _tidy(InstalledApp app) async {
    final dir = Directory(app.folder);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return;
      }
      final apks = <int, String>{};
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final match = _updateFileName.firstMatch(p.basename(entity.path));
        if (match == null) continue;
        final code = int.parse(match.group(1)!);
        if (code <= app.code) {
          await _delete(entity.path);
        } else if (match.group(3) == 'apk') {
          final other = apks[code];
          if (other != null) await _delete(other);
          apks[code] = entity.path;
        }
      }
      if (apks.isEmpty) return;
      final best = apks.keys.reduce(math.max);
      for (final entry in apks.entries) {
        if (entry.key != best) await _delete(entry.value);
      }
      _readyCode = best;
      _readyPath = apks[best];
      _stage = AppUpdateStage.ready;
    } catch (_) {}
  }

  void _readinessChanged() {
    if (_disposed || _app == null) return;
    final ready = _transport.ready;
    if (ready == _wasReady) return;
    _wasReady = ready;
    if (ready) {
      _sayHello();
      _resume();
    } else {
      _pause();
    }
    notifyListeners();
  }

  void _sayHello() {
    final app = _app;
    if (app == null) return;
    unawaited(_transport.send({'k': 'hello', 'code': app.code, 'serves': app.apk != null}));
  }

  void _onEvent(Object? raw) {
    if (_disposed || raw is! Map) return;
    switch (raw['k']) {
      case 'hello':
        _onHello(raw);
      case 'want':
        unawaited(_onWant(raw));
      case 'offer':
        unawaited(_onOffer(raw));
      case 'get':
        _onGet(raw);
      case 'none':
        _onNone(raw);
    }
  }

  void _onHello(Map raw) {
    final code = raw['code'];
    if (code is! int || code <= 0) return;
    _partnerCode = code;
    _partnerServes = raw['serves'] == true;
    _consider();
    notifyListeners();
  }

  bool get _partnerIsNewer {
    final app = _app;
    final partner = _partnerCode;
    return app != null && partner != null && partner > app.code && _partnerServes;
  }

  void _consider() {
    if (_app == null) return;
    final newer = _partnerIsNewer;
    final partner = _partnerCode;
    switch (_stage) {
      case AppUpdateStage.none:
        if (newer) _stage = AppUpdateStage.available;
      case AppUpdateStage.available:
        if (!newer) _stage = AppUpdateStage.none;
      case AppUpdateStage.fetching:
        if (newer && partner != _wantCode) {
          _stopFetching();
          _stage = AppUpdateStage.available;
        }
      case AppUpdateStage.ready:
      case AppUpdateStage.needsPermission:
        final ready = _readyCode;
        if (newer && ready != null && partner! > ready) {
          final old = _readyPath;
          _readyPath = null;
          _readyCode = null;
          if (old != null) unawaited(_delete(old));
          _stage = AppUpdateStage.available;
        }
      case AppUpdateStage.failed:
        if (!newer && _readyPath == null) _stage = AppUpdateStage.none;
      case AppUpdateStage.installing:
        break;
    }
  }

  Future<bool> fetch() async {
    await _loading;
    if (_disposed || !_partnerIsNewer) return false;
    final partner = _partnerCode!;
    if (_stage == AppUpdateStage.fetching && _wantCode == partner) return true;
    if (_readyCode == partner && _readyPath != null) return true;
    if (_stage != AppUpdateStage.available && _stage != AppUpdateStage.failed) return false;
    _wantCode = partner;
    _offer = null;
    _next = 0;
    _requestedUpTo = 0;
    _lastPieceAt = null;
    _stage = AppUpdateStage.fetching;
    notifyListeners();
    _resume();
    return true;
  }

  void _resume() {
    if (_stage != AppUpdateStage.fetching || !_transport.ready) return;
    final want = _wantCode;
    if (want == null) return;
    _askedAt = _clock.now();
    final offer = _offer;
    if (offer == null || offer.code != want) {
      unawaited(_transport.send({'k': 'want', 'code': want}));
      return;
    }
    _requestedUpTo = _next;
    _askMore();
  }

  void _pause() {
    _shareGen++;
    _asks.clear();
    _requestedUpTo = _next;
    unawaited(_closePart());
  }

  void _stopFetching() {
    final offer = _offer;
    _offer = null;
    _wantCode = null;
    _next = 0;
    _requestedUpTo = 0;
    unawaited(_closePart().then((_) async {
      if (offer != null) await _delete(_partPath(offer));
    }));
  }

  Future<void> _onOffer(Map raw) async {
    final app = _app;
    if (app == null || _stage != AppUpdateStage.fetching) return;
    final code = raw['code'];
    final size = raw['size'];
    final sha = raw['sha256'];
    final piece = raw['piece'];
    if (code is! int || code != _wantCode) return;
    if (size is! int || size <= 0 || size > appUpdateMaxBytes) return;
    if (sha is! String || !_sha256Hex.hasMatch(sha)) return;
    if (piece is! int || piece < appUpdateMinPieceBytes || piece > appUpdateMaxPieceBytes) return;
    final current = _offer;
    if (current != null && current.code == code && current.sha == sha && current.size == size && current.piece == piece) {
      _requestedUpTo = _next;
      _askMore();
      return;
    }
    await _closePart();
    if (_disposed || _stage != AppUpdateStage.fetching || code != _wantCode) return;
    final offer = _Offer(code: code, size: size, sha: sha, piece: piece);
    await _dropOtherParts(app, keep: _partPath(offer));
    var have = 0;
    try {
      final file = File(_partPath(offer));
      if (await file.exists()) have = await file.length();
    } catch (_) {}
    if (_disposed || _stage != AppUpdateStage.fetching || code != _wantCode) return;
    _offer = offer;
    _next = have >= size ? offer.total : math.min(have ~/ piece, offer.total);
    _requestedUpTo = _next;
    _lastPieceAt = _clock.now();
    notifyListeners();
    if (_next >= offer.total) {
      _queue(() => _finish(offer));
      return;
    }
    _askMore();
  }

  Future<void> _dropOtherParts(InstalledApp app, {required String keep}) async {
    try {
      await for (final entity in Directory(app.folder).list(followLinks: false)) {
        if (entity is! File || entity.path == keep) continue;
        if (p.basename(entity.path).endsWith('.part') && _updateFileName.hasMatch(p.basename(entity.path))) {
          await _delete(entity.path);
        }
      }
    } catch (_) {}
  }

  void _askMore() {
    final offer = _offer;
    if (offer == null || _stage != AppUpdateStage.fetching || !_transport.ready) return;
    if (_requestedUpTo < _next) _requestedUpTo = _next;
    if (_requestedUpTo - _next > appUpdateWindow ~/ 2) return;
    if (_requestedUpTo >= offer.total) return;
    final from = _requestedUpTo;
    final count = math.min(appUpdateWindow, offer.total - from);
    _requestedUpTo = from + count;
    _askedAt = _clock.now();
    unawaited(_transport.send({'k': 'get', 'code': offer.code, 'from': from, 'count': count}));
  }

  void _onPiece(Uint8List piece) {
    if (_disposed || _stage != AppUpdateStage.fetching) return;
    final offer = _offer;
    if (offer == null || piece.length <= appUpdatePieceHeaderBytes) return;
    final header = ByteData.sublistView(piece, 0, appUpdatePieceHeaderBytes);
    if (header.getUint32(0) != (offer.code & 0xffffffff)) return;
    final index = header.getUint32(4);
    final data = Uint8List.sublistView(piece, appUpdatePieceHeaderBytes);
    _queue(() => _take(offer, index, data));
  }

  Future<void> _queue(Future<void> Function() job) {
    final run = _writes.then((_) => job());
    _writes = run.catchError((Object _) {});
    return _writes;
  }

  Future<void> _take(_Offer offer, int index, Uint8List data) async {
    if (_disposed || !identical(_offer, offer) || _stage != AppUpdateStage.fetching) return;
    if (index != _next || index >= offer.total || data.length != offer.lengthOf(index)) return;
    try {
      final file = await _openPart(offer);
      await file.writeFrom(data);
    } catch (_) {
      await _closeFile();
      _fail(offer);
      return;
    }
    _next++;
    _lastPieceAt = _clock.now();
    notifyListeners();
    if (_next >= offer.total) {
      await _finish(offer);
      return;
    }
    _askMore();
  }

  Future<RandomAccessFile> _openPart(_Offer offer) async {
    final open = _part;
    if (open != null) return open;
    final at = math.min(_next * offer.piece, offer.size);
    final file = await File(_partPath(offer)).open(mode: FileMode.append);
    try {
      await file.truncate(at);
      await file.setPosition(at);
    } catch (_) {
      await file.close();
      rethrow;
    }
    _part = file;
    return file;
  }

  Future<void> _closeFile() async {
    final open = _part;
    _part = null;
    if (open == null) return;
    try {
      await open.close();
    } catch (_) {}
  }

  Future<void> _closePart() => _queue(_closeFile);

  Future<void> _finish(_Offer offer) async {
    await _closeFile();
    if (_disposed || !identical(_offer, offer)) return;
    _checking = true;
    notifyListeners();
    final path = _partPath(offer);
    var whole = false;
    try {
      final size = await File(path).length();
      whole = size == offer.size && await fileSha256(path) == offer.sha;
    } catch (_) {
      whole = false;
    }
    _checking = false;
    if (_disposed || !identical(_offer, offer)) return;
    if (!whole) {
      await _delete(path);
      _fail(offer);
      return;
    }
    final apk = _apkPath(offer);
    try {
      await File(path).rename(apk);
    } catch (_) {
      await _delete(path);
      _fail(offer);
      return;
    }
    _offer = null;
    _wantCode = null;
    _next = 0;
    _requestedUpTo = 0;
    _readyPath = apk;
    _readyCode = offer.code;
    _stage = AppUpdateStage.ready;
    notifyListeners();
  }

  void _fail(_Offer offer) {
    if (!identical(_offer, offer)) return;
    _offer = null;
    _wantCode = null;
    _next = 0;
    _requestedUpTo = 0;
    _stage = AppUpdateStage.failed;
    notifyListeners();
  }

  void _onNone(Map raw) {
    final code = raw['code'];
    if (_stage != AppUpdateStage.fetching || code != _wantCode) return;
    _stopFetching();
    _partnerServes = false;
    _stage = AppUpdateStage.failed;
    notifyListeners();
  }

  Future<void> _onWant(Map raw) async {
    final code = raw['code'];
    if (code is! int) return;
    final app = _app;
    final serving = app != null && code == app.code ? await _servingApk() : null;
    if (_disposed) return;
    if (serving == null || serving.code != code) {
      await _transport.send({'k': 'none', 'code': code});
      return;
    }
    _sharedPieces = 0;
    await _transport.send({
      'k': 'offer',
      'code': serving.code,
      'size': serving.size,
      'sha256': serving.sha,
      'piece': appUpdatePieceBytes,
    });
  }

  Future<_Serving?> _servingApk() {
    final cached = _serving;
    if (cached != null) return cached;
    final measuring = _measure();
    _serving = measuring;
    return measuring;
  }

  Future<_Serving?> _measure() async {
    final app = _app;
    final path = app?.apk;
    if (app == null || path == null) return null;
    try {
      final size = await File(path).length();
      if (size <= 0 || size > appUpdateMaxBytes) return null;
      final sha = await fileSha256(path);
      return _Serving(code: app.code, path: path, size: size, sha: sha);
    } catch (_) {
      _serving = null;
      return null;
    }
  }

  void _onGet(Map raw) {
    final app = _app;
    final code = raw['code'];
    final from = raw['from'];
    final count = raw['count'];
    if (app == null || app.apk == null || code != app.code) return;
    if (from is! int || count is! int || from < 0 || count <= 0 || count > appUpdateWindow * 2) return;
    _asks.add(_Ask(from, count));
    if (!_sharing) unawaited(_share(_shareGen));
  }

  Future<void> _share(int gen) async {
    _sharing = true;
    RandomAccessFile? file;
    try {
      final serving = await _servingApk();
      if (serving == null) {
        _asks.clear();
        return;
      }
      final total = (serving.size + appUpdatePieceBytes - 1) ~/ appUpdatePieceBytes;
      _shareTotal = total;
      file = await File(serving.path).open();
      while (_asks.isNotEmpty && gen == _shareGen && !_disposed) {
        final ask = _asks.removeAt(0);
        final end = math.min(ask.from + ask.count, total);
        for (var index = ask.from; index < end; index++) {
          if (gen != _shareGen || _disposed || !_transport.ready) return;
          final start = index * appUpdatePieceBytes;
          final length = math.min(appUpdatePieceBytes, serving.size - start);
          final data = Uint8List(length);
          await file.setPosition(start);
          final read = await file.readInto(data);
          if (read != length) {
            _asks.clear();
            return;
          }
          if (!await _transport.sendPiece(framePiece(serving.code, index, data))) {
            _asks.clear();
            return;
          }
          _sharedPieces = math.max(_sharedPieces, index + 1);
          _lastShareAt = _clock.now();
          _shareShown = true;
          notifyListeners();
        }
      }
    } catch (_) {
      _asks.clear();
    } finally {
      try {
        await file?.close();
      } catch (_) {}
      _sharing = false;
      if (gen != _shareGen && _asks.isNotEmpty && !_disposed) unawaited(_share(_shareGen));
    }
  }

  Future<bool> install() async {
    final platform = _platform;
    final path = _readyPath;
    if (_disposed || platform == null || path == null) return false;
    if (_stage != AppUpdateStage.ready && _stage != AppUpdateStage.needsPermission) return false;
    if (!await File(path).exists()) {
      _readyPath = null;
      _readyCode = null;
      _stage = AppUpdateStage.none;
      _consider();
      notifyListeners();
      return false;
    }
    if (!await platform.canInstall()) {
      _stage = AppUpdateStage.needsPermission;
      notifyListeners();
      await platform.allowInstalls();
      return false;
    }
    if (_disposed) return false;
    _stage = AppUpdateStage.installing;
    notifyListeners();
    final opened = await platform.install(path);
    if (!opened && !_disposed && _stage == AppUpdateStage.installing) {
      _stage = AppUpdateStage.ready;
      notifyListeners();
    }
    return opened;
  }

  void onForeground() {
    if (_disposed) return;
    switch (_stage) {
      case AppUpdateStage.needsPermission:
        unawaited(_afterPermission());
      case AppUpdateStage.installing:
        _stage = AppUpdateStage.ready;
        notifyListeners();
      default:
        break;
    }
  }

  Future<void> _afterPermission() async {
    final platform = _platform;
    if (platform == null || !await platform.canInstall()) return;
    if (_disposed || _stage != AppUpdateStage.needsPermission) return;
    await install();
  }

  void _tick() {
    if (_disposed) return;
    if (_stage == AppUpdateStage.fetching && _transport.ready && !_checking) {
      final last = math.max(_lastPieceAt ?? 0, _askedAt ?? 0);
      if (_clock.now() - last >= appUpdateStallMs) {
        _requestedUpTo = _next;
        _resume();
      }
    }
    final shown = sharing;
    if (_shareShown != shown) {
      _shareShown = shown;
      notifyListeners();
    }
  }

  String _partPath(_Offer offer) => p.join(_app!.folder, '${offer.code}-${offer.sha}.part');

  String _apkPath(_Offer offer) => p.join(_app!.folder, '${offer.code}-${offer.sha}.apk');

  Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    if (_platform != null) _transport.detach();
    _shareGen++;
    _asks.clear();
    unawaited(_closePart());
    super.dispose();
  }
}
