import 'dart:async';
import 'dart:convert';

import 'package:our_space_mobile/core/engine/p2p/peer_clock.dart';
import 'package:our_space_mobile/core/engine/p2p/sky_together_link.dart';
import 'package:our_space_mobile/core/engine/p2p/sky_together_wire.dart';

import '../p2p/support/fake_clock.dart';

class SkyPhoneClock implements PeerClock {
  SkyPhoneClock(this.timeline, this.offset);

  final FakePeerClock timeline;
  int offset;

  @override
  int now() => timeline.now() + offset;

  @override
  Timer after(Duration delay, void Function() callback) => timeline.after(delay, callback);

  @override
  Timer every(Duration interval, void Function() callback) => timeline.every(interval, callback);
}

class FakeSkyTransport implements SkyTogetherTransport {
  FakeSkyTransport(this._pair, this.name);

  final FakeSkyPair _pair;
  final String name;
  late final FakeSkyTransport other;
  final List<Map<String, Object?>> sent = [];
  final List<Object?> received = [];
  void Function()? _onReadiness;
  void Function(Object? event)? _onEvent;
  bool refuse = false;

  bool get attached => _onEvent != null;

  @override
  bool get ready => _pair.connected;

  @override
  void attach({required void Function() onReadiness, required void Function(Object? event) onEvent}) {
    _onReadiness = onReadiness;
    _onEvent = onEvent;
  }

  @override
  void detach() {
    _onReadiness = null;
    _onEvent = null;
  }

  @override
  Future<bool> send(Map<String, Object?> event) {
    if (!ready || refuse) return Future<bool>.value(false);
    sent.add(event);
    _pair._carry(other, jsonDecode(jsonEncode(event)));
    return Future<bool>.value(true);
  }

  void receive(Object? raw) {
    received.add(raw);
    _onEvent?.call(raw);
  }

  void readinessChanged() => _onReadiness?.call();

  List<Map<String, Object?>> sentOf(String kind) => [for (final e in sent) if (e['k'] == kind) e];
}

class FakeSkyPair {
  FakeSkyPair({
    int start = 1760000000000,
    int offsetA = 0,
    int offsetB = 0,
    this.latency = Duration.zero,
    this.ownerA = 'owner-aaaa1111',
    this.ownerB = 'owner-bbbb2222',
    this.connected = true,
  }) : timeline = FakePeerClock(start) {
    clockA = SkyPhoneClock(timeline, offsetA);
    clockB = SkyPhoneClock(timeline, offsetB);
    transportA = FakeSkyTransport(this, 'A');
    transportB = FakeSkyTransport(this, 'B');
    transportA.other = transportB;
    transportB.other = transportA;
    a = SkyTogetherLink(transport: transportA, owner: () => ownerA, clock: clockA, tag: 'tag-phone-a');
    b = SkyTogetherLink(transport: transportB, owner: () => ownerB, clock: clockB, tag: 'tag-phone-b');
  }

  final FakePeerClock timeline;
  late final SkyPhoneClock clockA;
  late final SkyPhoneClock clockB;
  late final FakeSkyTransport transportA;
  late final FakeSkyTransport transportB;
  late final SkyTogetherLink a;
  late final SkyTogetherLink b;
  String? ownerA;
  String? ownerB;
  bool connected;
  Duration latency;
  int _round = 0;

  SkyTogetherLink other(SkyTogetherLink side) => identical(side, a) ? b : a;

  FakeSkyTransport transportOf(SkyTogetherLink side) => identical(side, a) ? transportA : transportB;

  void _carry(FakeSkyTransport to, Object? raw) {
    final round = _round;
    timeline.after(latency, () {
      if (connected && round == _round) to.receive(raw);
    });
  }

  void connect() {
    if (connected) return;
    connected = true;
    _round++;
    transportA.readinessChanged();
    transportB.readinessChanged();
  }

  void drop() {
    if (!connected) return;
    connected = false;
    _round++;
    transportA.readinessChanged();
    transportB.readinessChanged();
  }

  void advance(Duration by) => timeline.advance(by);

  void flush() => timeline.advance(Duration.zero);

  void settle({Duration step = const Duration(milliseconds: 20), int rounds = 25}) {
    for (var i = 0; i < rounds; i++) {
      timeline.advance(step);
    }
  }

  void inject(SkyTogetherLink to, Object? raw) => transportOf(to).receive(raw);

  void injectEvent(SkyTogetherLink to, SkyTogetherEvent event) => inject(to, jsonDecode(jsonEncode(event.toWire())));

  int get sharedGap => (a.sharedNow() - b.sharedNow()).abs();

  void dispose() {
    a.dispose();
    b.dispose();
  }
}
