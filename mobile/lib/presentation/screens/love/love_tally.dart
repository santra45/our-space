import 'package:flutter/foundation.dart';

typedef LoveRecord = ({int count, int? at});

@immutable
class LoveTally {
  const LoveTally({
    required this.sent,
    required this.received,
    this.lastSentAt,
    this.lastReceivedAt,
    this.mine = const {},
  });

  static const LoveTally empty = LoveTally(sent: 0, received: 0);

  static const String recordPrefix = 'burst-';

  final int sent;
  final int received;
  final int? lastSentAt;
  final int? lastReceivedAt;
  final Map<String, LoveRecord> mine;

  bool get hasReceived => received > 0;

  factory LoveTally.fromRows(
    Iterable<Map<String, Object?>> rows, {
    required String ownRecordId,
    Set<String> myOwnerIds = const {},
  }) {
    var sent = 0;
    var received = 0;
    int? lastSent;
    int? lastReceived;
    final mine = <String, LoveRecord>{};
    for (final row in rows) {
      final id = row['id'];
      final count = row['count'];
      if (id is! String || count is! num || !count.isFinite || count <= 0) continue;
      if (row['deleted'] == true || row['_headerTampered'] == true || row['_tableTampered'] == true) continue;
      final amount = count.floor();
      final at = _stamp(row['lastSentAt']);
      if (isMine(id, ownRecordId: ownRecordId, myOwnerIds: myOwnerIds)) {
        sent += amount;
        lastSent = _later(lastSent, at);
        mine[id] = (count: amount, at: at);
      } else {
        received += amount;
        lastReceived = _later(lastReceived, at);
      }
    }
    return LoveTally(
      sent: sent,
      received: received,
      lastSentAt: lastSent,
      lastReceivedAt: lastReceived,
      mine: Map.unmodifiable(mine),
    );
  }

  static bool isMine(String recordId, {required String ownRecordId, Set<String> myOwnerIds = const {}}) {
    if (recordId == ownRecordId) return true;
    if (!recordId.startsWith(recordPrefix)) return false;
    return myOwnerIds.contains(recordId.substring(recordPrefix.length));
  }

  static int? _stamp(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) return null;
    return value.floor();
  }

  static int? _later(int? current, int? next) {
    if (next == null) return current;
    if (current == null || next > current) return next;
    return current;
  }

  @override
  bool operator ==(Object other) =>
      other is LoveTally &&
      other.sent == sent &&
      other.received == received &&
      other.lastSentAt == lastSentAt &&
      other.lastReceivedAt == lastReceivedAt &&
      mapEquals(other.mine, mine);

  @override
  int get hashCode => Object.hash(sent, received, lastSentAt, lastReceivedAt, mine.length);
}

String formatLoveCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
