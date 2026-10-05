class Letter {
  final String id;
  final String title;
  final String body;
  final String authorName;
  final String? unlockDate;
  final bool isSealed;
  final bool isOpened;
  final Map<String, dynamic>? timeLockPayload;
  final int updatedAt;
  final bool deleted;

  Letter({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    this.unlockDate,
    this.isSealed = false,
    this.isOpened = false,
    this.timeLockPayload,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Letter.fromMap(Map<String, dynamic> map) {
    return Letter(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      unlockDate: map['unlockDate'] as String?,
      isSealed: map['isSealed'] == true,
      isOpened: map['isOpened'] == true,
      timeLockPayload: map['timeLockPayload'] as Map<String, dynamic>?,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'authorName': authorName,
      'unlockDate': unlockDate,
      'isSealed': isSealed,
      'isOpened': isOpened,
      if (timeLockPayload != null) 'timeLockPayload': timeLockPayload,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  Letter copyWith({
    String? title,
    String? body,
    String? authorName,
    String? unlockDate,
    bool? isSealed,
    bool? isOpened,
    Map<String, dynamic>? timeLockPayload,
    int? updatedAt,
    bool? deleted,
  }) {
    return Letter(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      authorName: authorName ?? this.authorName,
      unlockDate: unlockDate ?? this.unlockDate,
      isSealed: isSealed ?? this.isSealed,
      isOpened: isOpened ?? this.isOpened,
      timeLockPayload: timeLockPayload ?? this.timeLockPayload,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
