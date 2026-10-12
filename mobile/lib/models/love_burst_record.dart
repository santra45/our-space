import 'plain_record.dart';

class LoveBurstRecord extends PlainRecord {
  LoveBurstRecord(super.fields);

  int get count => readInt(fields['count']) ?? 0;

  int? get lastSentAt => readInt(fields['lastSentAt']);
}

class UnseenBursts {
  const UnseenBursts({required this.total, required this.lastSentAt, required this.records});

  static const UnseenBursts empty = UnseenBursts(total: 0, lastSentAt: 0, records: []);

  final int total;
  final int lastSentAt;
  final List<BurstCount> records;
}

class BurstCount {
  const BurstCount({required this.id, required this.count});

  final String id;
  final int count;
}
