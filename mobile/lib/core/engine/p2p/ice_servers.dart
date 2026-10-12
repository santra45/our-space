import '../crypto/js_compat.dart';

const List<String> stunUrls = [
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:global.stun.twilio.com:3478',
];

const List<String> defaultTurnUrls = [
  'turn:openrelay.metered.ca:80',
  'turn:openrelay.metered.ca:443',
  'turn:openrelay.metered.ca:443?transport=tcp',
];

const String defaultTurnUsername = 'openrelayproject';
const String defaultTurnCredential = 'openrelayproject';

const Map<String, String> environmentTurnConfig = {
  'VITE_TURN_URLS': String.fromEnvironment('VITE_TURN_URLS'),
  'VITE_TURN_USERNAME': String.fromEnvironment('VITE_TURN_USERNAME'),
  'VITE_TURN_CREDENTIAL': String.fromEnvironment('VITE_TURN_CREDENTIAL'),
};

class TurnConfig {
  const TurnConfig({required this.urls, required this.username, required this.credential});

  final List<String> urls;
  final String username;
  final String credential;
}

String _readEnv(Map<String, String> source, String name) => jsTrim(source[name] ?? '');

List<String> _parseUrlList(String raw) =>
    raw.split(RegExp(r'[\s,]+')).map(jsTrim).where((url) => url.isNotEmpty).toList();

void Function(String message) iceServersWarn = (_) {};

TurnConfig resolveTurnConfig([Map<String, String>? overrides]) {
  final source = overrides ?? environmentTurnConfig;
  final urls = _parseUrlList(_readEnv(source, 'VITE_TURN_URLS'));
  final username = _readEnv(source, 'VITE_TURN_USERNAME');
  final credential = _readEnv(source, 'VITE_TURN_CREDENTIAL');

  if (urls.isNotEmpty && username.isNotEmpty && credential.isNotEmpty) {
    return TurnConfig(urls: urls, username: username, credential: credential);
  }
  if (urls.isNotEmpty || username.isNotEmpty || credential.isNotEmpty) {
    iceServersWarn(
      '[iceServers] Partial TURN configuration ignored - all three of '
      'VITE_TURN_URLS, VITE_TURN_USERNAME and VITE_TURN_CREDENTIAL are needed.',
    );
  }
  return TurnConfig(
    urls: [...defaultTurnUrls],
    username: defaultTurnUsername,
    credential: defaultTurnCredential,
  );
}

List<Map<String, Object?>> buildIceServers([Map<String, String>? overrides]) {
  final servers = <Map<String, Object?>>[
    for (final url in stunUrls) {'urls': url},
  ];
  final turn = resolveTurnConfig(overrides);
  if (turn.urls.isNotEmpty) {
    servers.add({
      'urls': [...turn.urls],
      'username': turn.username,
      'credential': turn.credential,
    });
  }
  return servers;
}

bool hasTurnConfigured([Map<String, String>? overrides]) => resolveTurnConfig(overrides).urls.isNotEmpty;
