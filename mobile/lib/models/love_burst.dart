class LoveBurst {
  final String id;
  final String senderPersonId;
  final int count;
  final int? receivedAt;
  final int updatedAt;
  final bool deleted;

  LoveBurst({
    required this.id,
    required this.senderPersonId,
    required this.count,
    this.receivedAt,
    required this.updatedAt,
    this.deleted = false,
  });

  factory LoveBurst.fromMap(Map<String, dynamic> map) {
    return LoveBurst(
      id: map['id'] as String,
      senderPersonId: map['senderPersonId'] as String? ?? '',
      count: (map['count'] as num?)?.toInt() ?? 1,
      receivedAt: (map['receivedAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderPersonId': senderPersonId,
      'count': count,
      'receivedAt': receivedAt,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  LoveBurst copyWith({
    String? senderPersonId,
    int? count,
    int? receivedAt,
    int? updatedAt,
    bool? deleted,
  }) {
    return LoveBurst(
      id: id,
      senderPersonId: senderPersonId ?? this.senderPersonId,
      count: count ?? this.count,
      receivedAt: receivedAt ?? this.receivedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
