import 'dart:convert';
import 'dart:io';

Map<String, Object?> readP2pFixture(String name) {
  final file = File('test/p2p/fixtures/$name');
  if (!file.existsSync()) {
    throw StateError('Missing test/p2p/fixtures/$name. Run "node test/p2p/tool/capture_web_peer.mjs" from the mobile folder.');
  }
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}
