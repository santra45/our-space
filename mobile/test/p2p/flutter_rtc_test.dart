import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/flutter_rtc.dart';
import 'package:our_space_mobile/core/engine/p2p/ice_servers.dart';
import 'package:our_space_mobile/core/engine/p2p/rtc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel('FlutterWebRTC.Method');
  final calls = <MethodCall>[];
  final sinks = <String, MockStreamHandlerEventSink>{};

  void listenTo(String name) {
    messenger.setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(onListen: (arguments, sink) => sinks[name] = sink),
    );
  }

  setUp(() {
    calls.clear();
    sinks.clear();
    listenTo('FlutterWebRTC/peerConnectionEventpc1');
    listenTo('FlutterWebRTC/dataChannelEventpc1dc1');
    listenTo('FlutterWebRTC/dataChannelEventpc1dc2');
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'createPeerConnection':
          return {'peerConnectionId': 'pc1'};
        case 'createDataChannel':
          return {'id': 1, 'label': (call.arguments as Map)['label'], 'flutterId': 'dc1'};
        case 'createOffer':
          return {'sdp': 'v=0 phone offer', 'type': 'offer'};
        case 'createAnswer':
          return {'sdp': 'v=0 phone answer', 'type': 'answer'};
        case 'getStats':
          return {
            'stats': [
              {
                'id': 'pair',
                'type': 'candidate-pair',
                'timestamp': 1.0,
                'values': {'nominated': true, 'localCandidateId': 'l', 'remoteCandidateId': 'r'},
              },
            ],
          };
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
  });

  MethodCall called(String name) => calls.lastWhere((c) => c.method == name);

  test('the adapter drives flutter_webrtc the way PeerJS drives the browser', () async {
    final session = await createFlutterRtcSession({'iceServers': buildIceServers()});
    final create = called('createPeerConnection').arguments as Map;
    expect(create['configuration'], {'iceServers': buildIceServers(), 'sdpSemantics': 'unified-plan'});

    final channel = await session.createDataChannel('dc_abc', ordered: true);
    final dict = (called('createDataChannel').arguments as Map)['dataChannelDict'] as Map;
    expect(dict['ordered'], isTrue);
    expect(dict['id'], -1);
    expect(dict['protocol'], '');
    expect(dict['negotiated'], isFalse);
    expect(dict.containsKey('maxRetransmits'), isFalse);
    expect(channel.label, 'dc_abc');
    expect(channel.readyState, 'connecting');

    expect(await session.createOffer(), {'type': 'offer', 'sdp': 'v=0 phone offer'});
    expect((called('createOffer').arguments as Map)['constraints'], isEmpty);
    await session.setLocalDescription({'type': 'offer', 'sdp': 'v=0 phone offer'});
    expect((called('setLocalDescription').arguments as Map)['description'], {'sdp': 'v=0 phone offer', 'type': 'offer'});
    await session.setRemoteDescription({'type': 'answer', 'sdp': 'v=0 web answer'});
    expect((called('setRemoteDescription').arguments as Map)['description'], {'sdp': 'v=0 web answer', 'type': 'answer'});
    await session.addIceCandidate({'candidate': 'candidate:1', 'sdpMid': '0', 'sdpMLineIndex': 0, 'usernameFragment': 'u'});
    expect((called('addCandidate').arguments as Map)['candidate'], {'candidate': 'candidate:1', 'sdpMid': '0', 'sdpMLineIndex': 0});

    final stats = await session.getStats();
    expect(stats.single['type'], 'candidate-pair');
    expect(stats.single['nominated'], isTrue);
    expect(stats.single['localCandidateId'], 'l');

    final candidates = <Map<String, Object?>>[];
    final ice = <String>[];
    session.onIceCandidate = candidates.add;
    session.onIceConnectionState = ice.add;
    final peerSink = sinks['FlutterWebRTC/peerConnectionEventpc1']!;
    peerSink.success({
      'event': 'onCandidate',
      'candidate': {'candidate': 'candidate:2', 'sdpMid': '0', 'sdpMLineIndex': 0},
    });
    peerSink.success({
      'event': 'onCandidate',
      'candidate': {'candidate': '', 'sdpMid': '0', 'sdpMLineIndex': 0},
    });
    peerSink.success({'event': 'iceConnectionState', 'state': 'connected'});
    await pumpEventQueue();
    expect(candidates, [
      {'candidate': 'candidate:2', 'sdpMid': '0', 'sdpMLineIndex': 0},
    ]);
    expect(ice, ['connected']);
    expect(session.iceConnectionState, 'connected');

    var opened = 0;
    final received = <Uint8List>[];
    var closed = 0;
    channel.onOpen = () => opened++;
    channel.onBinary = received.add;
    channel.onClose = () => closed++;
    final channelSink = sinks['FlutterWebRTC/dataChannelEventpc1dc1']!;
    channelSink.success({'event': 'dataChannelStateChanged', 'id': 1, 'state': 'open'});
    channelSink.success({'event': 'dataChannelReceiveMessage', 'id': 1, 'type': 'binary', 'data': Uint8List.fromList([1, 2, 3])});
    await pumpEventQueue();
    expect(opened, 1);
    expect(channel.readyState, 'open');
    expect(received.single, [1, 2, 3]);

    await channel.send(Uint8List.fromList([9, 8]));
    final send = called('dataChannelSend').arguments as Map;
    expect(send['type'], 'binary');
    expect(send['data'], [9, 8]);
    expect(send['dataChannelId'], 'dc1');

    channelSink.success({'event': 'dataChannelStateChanged', 'id': 1, 'state': 'closed'});
    await pumpEventQueue();
    expect(closed, 1);

    await session.close();
    expect(calls.map((c) => c.method), containsAll(['peerConnectionClose', 'peerConnectionDispose']));
    expect(session.signalingState, 'closed');
  });

  test('a channel the partner opened arrives open and says so once its listener is set', () async {
    final session = await createFlutterRtcSession({'iceServers': buildIceServers()});
    final arrived = Completer<RtcChannel>();
    session.onDataChannel = arrived.complete;
    sinks['FlutterWebRTC/peerConnectionEventpc1']!.success({
      'event': 'didOpenDataChannel',
      'id': 2,
      'label': 'dc_web',
      'flutterId': 'dc2',
    });
    final channel = await arrived.future;
    expect(channel.label, 'dc_web');
    expect(channel.readyState, 'open');
    var opened = 0;
    channel.onOpen = () => opened++;
    await pumpEventQueue();
    expect(opened, 1);
    channel.onOpen = () => opened++;
    await pumpEventQueue();
    expect(opened, 1);
    await session.close();
  });
}
