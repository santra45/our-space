import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/binary_pack.dart';
import 'package:our_space_mobile/core/engine/p2p/ice_servers.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peerjs.dart';

import 'support/fake_clock.dart';
import 'support/fake_rtc.dart';
import 'support/fixtures.dart';

class Rig {
  Rig({String? id = 'love-phone0000', String token = 'tok123abc'}) {
    peer = PeerJsPeer(
      id,
      options: PeerJsOptions(token: token, iceServers: buildIceServers()),
      connector: sockets.connect,
      rtcFactory: rtc.create,
      clock: clock,
    );
    peer.onOpen = opened.add;
    peer.onError = errors.add;
    peer.onDisconnected = disconnects.add;
    peer.onConnection = connections.add;
  }

  final FakeSockets sockets = FakeSockets();
  final FakeRtc rtc = FakeRtc();
  final FakePeerClock clock = FakePeerClock();
  late final PeerJsPeer peer;
  final List<String> opened = [];
  final List<PeerError> errors = [];
  final List<String?> disconnects = [];
  final List<PeerLink> connections = [];

  FakeSignalSocket get socket => sockets.last;

  void openServer() {
    socket.serverOpen();
    socket.serverSend({'type': 'OPEN'});
  }

  List<Map<String, Object?>> sentOf(String type) => [for (final m in socket.sentMessages) if (m['type'] == type) m];
}

void main() {
  group('signalling server', () {
    test('connects to the PeerJS cloud with the same URL and heartbeat as the web', () async {
      final rig = Rig();
      expect(
        rig.socket.url.toString(),
        'wss://0.peerjs.com:443/peerjs?key=peerjs&id=love-phone0000&token=tok123abc&version=1.5.5',
      );
      expect(rig.peer.open, isFalse);
      rig.openServer();
      expect(rig.opened, ['love-phone0000']);
      expect(rig.peer.open, isTrue);
      expect(rig.peer.id, 'love-phone0000');

      rig.clock.advance(const Duration(milliseconds: 4999));
      expect(rig.socket.sent, isEmpty);
      rig.clock.advance(const Duration(milliseconds: 1));
      expect(rig.socket.sent, ['{"type":"HEARTBEAT"}']);
      rig.clock.advance(const Duration(seconds: 5));
      expect(rig.socket.sent, hasLength(2));
    });

    test('a taken id before opening destroys the peer and says unavailable-id', () {
      final rig = Rig();
      rig.socket.serverOpen();
      rig.socket.serverSend({
        'type': 'ID-TAKEN',
        'payload': {'msg': 'ID is taken'},
      });
      expect(rig.errors.single.type, PeerError.unavailableId);
      expect(rig.peer.destroyed, isTrue);
      expect(rig.disconnects, hasLength(1));
      expect(rig.sockets.created, hasLength(1));
    });

    test('server errors, bad keys and expired offers become the PeerJS error types', () {
      final rig = Rig();
      rig.openServer();
      rig.socket.serverSend({'type': 'EXPIRE', 'src': 'love-gone0000'});
      expect(rig.errors.last.type, PeerError.peerUnavailable);
      expect(rig.peer.disconnected, isFalse);
      rig.socket.serverSend({
        'type': 'ERROR',
        'payload': {'msg': 'boom'},
      });
      expect(rig.errors.last.type, PeerError.serverError);
      expect(rig.peer.disconnected, isTrue);
      expect(rig.peer.destroyed, isFalse);

      final other = Rig();
      other.socket.serverOpen();
      other.socket.serverSend({'type': 'INVALID-KEY'});
      expect(other.errors.single.type, PeerError.invalidKey);
      expect(other.peer.destroyed, isTrue);
    });

    test('losing the server reports network trouble and reconnects with the same id', () {
      final rig = Rig();
      rig.openServer();
      rig.socket.serverClose();
      expect(rig.errors.single.type, PeerError.network);
      expect(rig.errors.single.message, 'Lost connection to server.');
      expect(rig.disconnects, ['love-phone0000']);
      expect(rig.peer.disconnected, isTrue);
      expect(rig.peer.open, isFalse);

      rig.peer.reconnect();
      expect(rig.sockets.created, hasLength(2));
      expect(rig.socket.url.queryParameters['id'], 'love-phone0000');
      rig.openServer();
      expect(rig.opened, ['love-phone0000', 'love-phone0000']);
    });

    test('a destroyed peer stays down and cannot dial', () {
      final rig = Rig();
      rig.openServer();
      rig.peer.destroy();
      expect(rig.peer.destroyed, isTrue);
      expect(rig.peer.disconnected, isTrue);
      expect(() => rig.peer.reconnect(), throwsStateError);
      expect(rig.peer.connect('love-web00000'), isNull);
      expect(rig.errors.last.type, PeerError.disconnected);
    });

    test('an id PeerJS would refuse is rejected on the next tick', () {
      final rig = Rig(id: 'bad id!');
      expect(rig.sockets.created, isEmpty);
      rig.clock.advance(Duration.zero);
      expect(rig.errors.single.type, PeerError.invalidId);
      expect(rig.peer.destroyed, isTrue);
      expect(peerJsValidateId('love-a1b2c3'), isTrue);
    });

    test('options normalise the path and always use TLS for the cloud', () {
      final options = PeerJsOptions(path: 'myapp');
      expect(options.path, '/myapp/');
      expect(options.secure, isTrue);
      expect(PeerJsOptions(host: 'example.test', secure: false).secure, isFalse);
      expect(peerJsRandomToken(), matches(RegExp(r'^[0-9a-z]{11}$')));
    });
  });

  group('dialing', () {
    test('sends the same OFFER, candidates and ANSWER handling as PeerJS', () async {
      final rig = Rig();
      rig.openServer();
      final link = rig.peer.connect('love-web00000', reliable: true)!;
      await drain();

      final session = rig.rtc.last;
      expect(session.configuration, {'iceServers': buildIceServers()});
      expect(session.calls, ['createDataChannel', 'createOffer', 'setLocalDescription:offer']);
      final channel = session.channels.single;
      expect(channel.ordered, isTrue);

      final offer = rig.sentOf('OFFER').single;
      expect(offer.keys.toList(), ['type', 'payload', 'dst']);
      final payload = (offer['payload'] as Map).cast<String, Object?>();
      expect(payload.keys.toList(), ['sdp', 'type', 'connectionId', 'label', 'reliable', 'serialization']);
      final connectionId = payload['connectionId'] as String;
      expect(connectionId, matches(RegExp(r'^dc_[0-9a-z]{11}$')));
      expect(payload['sdp'], {'type': 'offer', 'sdp': 'v=0 offer 1'});
      expect(payload['type'], 'data');
      expect(payload['label'], connectionId);
      expect(payload['reliable'], isTrue);
      expect(payload['serialization'], 'binary');
      expect(offer['dst'], 'love-web00000');
      expect(channel.label, connectionId);

      session.emitCandidate({'candidate': '', 'sdpMid': '0', 'sdpMLineIndex': 0});
      session.emitCandidate({'candidate': 'candidate:1 1 udp 1 10.0.0.2 5000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0});
      expect(rig.sentOf('CANDIDATE').single, {
        'type': 'CANDIDATE',
        'payload': {
          'candidate': {'candidate': 'candidate:1 1 udp 1 10.0.0.2 5000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0},
          'type': 'data',
          'connectionId': connectionId,
        },
        'dst': 'love-web00000',
      });

      final remoteCandidate = {'candidate': 'candidate:2 1 udp 1 10.0.0.3 6000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0, 'usernameFragment': 'abcd'};
      rig.socket.serverSend({
        'type': 'CANDIDATE',
        'src': 'love-web00000',
        'payload': {'candidate': remoteCandidate, 'type': 'data', 'connectionId': connectionId},
      });
      await drain();
      expect(session.addedCandidates, isEmpty);
      rig.socket.serverSend({
        'type': 'ANSWER',
        'src': 'love-web00000',
        'payload': {
          'sdp': {'type': 'answer', 'sdp': 'v=0 answer'},
          'type': 'data',
          'connectionId': connectionId,
        },
      });
      await drain();
      expect(session.remoteDescription, {'type': 'answer', 'sdp': 'v=0 answer'});
      expect(session.addedCandidates.single, remoteCandidate);

      var opened = 0;
      link.onOpen = () => opened++;
      expect(link.open, isFalse);
      channel.openNow();
      expect(opened, 1);
      expect(link.open, isTrue);
      expect(link.peer, 'love-web00000');
    });

    test('candidates found before the offer is sent wait for it', () async {
      final rig = Rig();
      rig.openServer();
      final hold = Completer<void>();
      rig.rtc.holdLocal = hold;
      rig.peer.connect('love-web00000');
      await drain();
      final session = rig.rtc.last;
      expect(session.calls.last, 'setLocalDescription:offer');
      session.emitCandidate({'candidate': 'candidate:early', 'sdpMid': '0', 'sdpMLineIndex': 0});
      expect(rig.socket.sentMessages, isEmpty);
      hold.complete();
      await drain();
      expect([for (final m in rig.socket.sentMessages) m['type']], ['OFFER', 'CANDIDATE']);
    });
  });

  group('answering', () {
    test('answers an OFFER, replays early candidates and opens on the remote channel', () async {
      final rig = Rig();
      rig.openServer();
      final early = {'candidate': 'candidate:3 1 udp 1 10.0.0.4 7000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0};
      rig.socket.serverSend({
        'type': 'CANDIDATE',
        'src': 'love-web00000',
        'payload': {'candidate': early, 'type': 'data', 'connectionId': 'dc_webconn01'},
      });
      rig.socket.serverSend({
        'type': 'OFFER',
        'src': 'love-web00000',
        'dst': 'love-phone0000',
        'payload': {
          'sdp': {'type': 'offer', 'sdp': 'v=0 web offer'},
          'type': 'data',
          'connectionId': 'dc_webconn01',
          'label': 'dc_webconn01',
          'reliable': true,
          'serialization': 'binary',
        },
      });
      expect(rig.connections, hasLength(1));
      final link = rig.connections.single;
      expect(link.peer, 'love-web00000');
      await drain();

      final session = rig.rtc.last;
      expect(session.calls.first, 'setRemoteDescription:offer');
      expect(session.calls.where((c) => c != 'addIceCandidate'), [
        'setRemoteDescription:offer',
        'createAnswer',
        'setLocalDescription:answer',
      ]);
      expect(session.calls.indexOf('addIceCandidate'), greaterThan(0));
      expect(session.addedCandidates.single, early);
      expect(rig.sentOf('ANSWER').single, {
        'type': 'ANSWER',
        'payload': {
          'sdp': {'type': 'answer', 'sdp': 'v=0 answer'},
          'type': 'data',
          'connectionId': 'dc_webconn01',
        },
        'dst': 'love-web00000',
      });

      var opened = 0;
      link.onOpen = () => opened++;
      final channel = FakeRtcChannel('dc_webconn01');
      session.emitDataChannel(channel);
      channel.openNow();
      expect(opened, 1);
      expect(link.open, isTrue);
    });

    test('a LEAVE from the other side closes our connection to it', () async {
      final rig = Rig();
      rig.openServer();
      final link = rig.peer.connect('love-web00000')!;
      await drain();
      var closed = 0;
      link.onClose = () => closed++;
      rig.rtc.last.channels.single.openNow();
      rig.socket.serverSend({'type': 'LEAVE', 'src': 'love-web00000'});
      expect(closed, 1);
      expect(link.open, isFalse);
      expect(rig.rtc.last.closed, isTrue);
    });
  });

  group('data channel', () {
    final vectors = readP2pFixture('binary_pack_vectors.json');
    final chunking = (vectors['chunking'] as Map).cast<String, Object?>();
    final frames = [for (final f in chunking['frames'] as List) Uint8List.fromList(base64.decode(f as String))];
    final message = binaryUnpack(base64.decode(chunking['message'] as String));

    Future<(Rig, PeerLink, FakeRtcChannel)> openLink() async {
      final rig = Rig();
      rig.openServer();
      final link = rig.peer.connect('love-web00000')!;
      await drain();
      final channel = rig.rtc.last.channels.single;
      channel.openNow();
      return (rig, link, channel);
    }

    test('sends BinaryPack frames chunked exactly like the web connection', () async {
      final (_, link, channel) = await openLink();
      link.send({'protocol': 'SWEETHEART_V2', 'payload': {'ciphertext': 'abc', 'iv': 'def'}});
      expect(channel.sent, hasLength(1));
      expect(binaryUnpack(channel.sent.single), {'protocol': 'SWEETHEART_V2', 'payload': {'ciphertext': 'abc', 'iv': 'def'}});
      channel.sent.clear();
      link.send(message);
      expect([for (final f in channel.sent) base64.encode(f)], [for (final f in frames) base64.encode(f)]);
    });

    test('puts web chunks back together and honours a close request', () async {
      final (_, link, channel) = await openLink();
      final received = <Object?>[];
      var closed = 0;
      link.onData = received.add;
      link.onClose = () => closed++;
      for (final frame in frames) {
        channel.deliver(frame);
      }
      expect(received, hasLength(1));
      expect(jsonEncode(received.single), jsonEncode(message));
      channel.deliver(binaryPack({
        '__peerData': {'type': 'close'},
      }));
      expect(closed, 1);
      expect(link.open, isFalse);
    });

    test('waits while the channel buffer is over 8 MB, then sends in order', () async {
      final (rig, link, channel) = await openLink();
      channel.bufferedAmount = peerJsMaxBufferedAmount + 1;
      link.send({'protocol': 'SWEETHEART_V2', 'payload': {'ciphertext': 'one', 'iv': 'x'}});
      link.send({'protocol': 'SWEETHEART_V2', 'payload': {'ciphertext': 'two', 'iv': 'x'}});
      expect(channel.sent, isEmpty);
      rig.clock.advance(const Duration(milliseconds: 50));
      expect(channel.sent, isEmpty);
      channel.bufferedAmount = 0;
      rig.clock.advance(const Duration(milliseconds: 50));
      expect([for (final f in channel.sent) ((binaryUnpack(f) as Map)['payload'] as Map)['ciphertext']], ['one', 'two']);
    });

    test('sending before the channel opens is reported, not sent', () async {
      final rig = Rig();
      rig.openServer();
      final link = rig.peer.connect('love-web00000')!;
      final errors = <Object>[];
      link.onError = errors.add;
      link.send({'a': 1});
      expect((errors.single as PeerError).type, 'not-open-yet');
    });

    test('an ICE failure is reported as a connection error before route listeners hear it', () async {
      final (rig, link, _) = await openLink();
      final order = <String>[];
      link.onError = (error) => order.add('error:${(error as PeerError).type}');
      link.onClose = () => order.add('close');
      link.route!.addIceListener((state) => order.add('route:$state'));
      rig.rtc.last.emitIce('failed');
      expect(order, ['error:negotiation-failed', 'close', 'route:failed']);
      expect(link.open, isFalse);
    });

    test('the remote channel closing closes the link once', () async {
      final (_, link, channel) = await openLink();
      var closed = 0;
      link.onClose = () => closed++;
      channel.closeRemote();
      link.close();
      expect(closed, 1);
    });
  });

  test('ICE servers are the web list: three STUN servers then the open relay TURN', () {
    final servers = buildIceServers();
    expect(servers, [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
      {
        'urls': ['turn:openrelay.metered.ca:80', 'turn:openrelay.metered.ca:443', 'turn:openrelay.metered.ca:443?transport=tcp'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ]);
    final custom = buildIceServers({
      'VITE_TURN_URLS': ' turn:a.example:3478, turns:b.example:5349 ',
      'VITE_TURN_USERNAME': 'u',
      'VITE_TURN_CREDENTIAL': 'p',
    });
    expect(custom.last, {
      'urls': ['turn:a.example:3478', 'turns:b.example:5349'],
      'username': 'u',
      'credential': 'p',
    });
    final warnings = <String>[];
    iceServersWarn = warnings.add;
    expect(buildIceServers({'VITE_TURN_URLS': 'turn:a.example'}).last['username'], 'openrelayproject');
    expect(warnings.single, contains('Partial TURN configuration ignored'));
    iceServersWarn = (_) {};
    expect(hasTurnConfigured(), isTrue);
  });
}
