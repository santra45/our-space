import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class FakeMailboxWorker extends http.BaseClient {
  FakeMailboxWorker({
    required this.token,
    this.allowedOrigins = const ['https://sameskytonight.vercel.app', 'http://localhost:5173'],
    Map<String, Uint8List>? seed,
  }) : objects = seed ?? <String, Uint8List>{};

  static const int maxObjectBytes = 16 * 1024 * 1024;

  static final RegExp path = RegExp(
    r'^/m/([0-9a-f]{32,64})/([A-Za-z0-9_-]{8,64})/(manifest|rec/[A-Za-z0-9]{1,32}/[A-Za-z0-9_-]{1,255})$',
  );

  final String token;
  final List<String> allowedOrigins;
  final Map<String, Uint8List> objects;
  final List<String> calls = [];
  bool offline = false;
  final Set<String> failPuts = {};

  static FakeMailboxWorker fromKvDump(Map<String, Object?> dump, {required String token}) {
    final seed = <String, Uint8List>{};
    dump.forEach((key, value) {
      seed[key] = Uint8List.fromList(utf8.encode(value as String));
    });
    return FakeMailboxWorker(token: token, seed: seed);
  }

  Map<String, String> kvDump() => {
        for (final entry in objects.entries) entry.key: utf8.decode(entry.value),
      };

  http.StreamedResponse _reply(int status, [List<int>? body]) => http.StreamedResponse(
        Stream<List<int>>.fromIterable([body ?? const <int>[]]),
        status,
        headers: {
          'content-type': 'application/octet-stream',
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        },
      );

  bool _safeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw http.ClientException('offline', request.url);
    final method = request.method.toUpperCase();
    calls.add('$method ${request.url.path}');

    if (method == 'OPTIONS') return _reply(204);

    final origin = request.headers['Origin'] ?? request.headers['origin'] ?? '';
    if (origin.isEmpty || !allowedOrigins.contains(origin)) return _reply(403);

    final auth = request.headers['Authorization'] ?? request.headers['authorization'] ?? '';
    if (!_safeEqual(auth, 'Bearer $token')) return _reply(401);

    final match = path.firstMatch(request.url.path);
    if (match == null) return _reply(404);
    final key = '${match.group(1)}/${match.group(2)}/${match.group(3)}';

    if (method == 'GET') {
      final body = objects[key];
      if (body == null) return _reply(404);
      return _reply(200, body);
    }

    if (method == 'PUT') {
      final bytes = request is http.Request ? request.bodyBytes : await request.finalize().toBytes();
      if (bytes.length > maxObjectBytes) return _reply(413, utf8.encode('Too large'));
      if (failPuts.contains(key)) return _reply(500);
      objects[key] = Uint8List.fromList(bytes);
      return _reply(204);
    }

    return _reply(405);
  }
}
