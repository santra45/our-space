class Person {
  final String id; // 'slot-0' | 'slot-1'
  final String personId;
  final String name;
  final String pronoun; // 'she' | 'he' | 'they'
  final List<String> deviceIds;
  final int? lastActiveAt;
  final int updatedAt;
  final bool deleted;

  Person({
    required this.id,
    required this.personId,
    required this.name,
    this.pronoun = 'they',
    this.deviceIds = const [],
    this.lastActiveAt,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as String,
      personId: map['personId'] as String? ?? map['id'] as String,
      name: map['name'] as String? ?? 'Partner',
      pronoun: map['pronoun'] as String? ?? 'they',
      deviceIds: (map['deviceIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      lastActiveAt: (map['lastActiveAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'personId': personId,
      'name': name,
      'pronoun': pronoun,
      'deviceIds': deviceIds,
      'lastActiveAt': lastActiveAt,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  Person copyWith({
    String? name,
    String? pronoun,
    List<String>? deviceIds,
    int? lastActiveAt,
    int? updatedAt,
    bool? deleted,
  }) {
    return Person(
      id: id,
      personId: personId,
      name: name ?? this.name,
      pronoun: pronoun ?? this.pronoun,
      deviceIds: deviceIds ?? this.deviceIds,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
