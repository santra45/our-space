class DailyAnswer {
  final String id;
  final String dayKey;
  final String questionId;
  final String personId;
  final String authorName;
  final String text;
  final int answeredAt;
  final int updatedAt;
  final bool deleted;

  DailyAnswer({
    required this.id,
    required this.dayKey,
    required this.questionId,
    required this.personId,
    required this.authorName,
    required this.text,
    required this.answeredAt,
    required this.updatedAt,
    this.deleted = false,
  });

  factory DailyAnswer.fromMap(Map<String, dynamic> map) {
    return DailyAnswer(
      id: map['id'] as String,
      dayKey: map['dayKey'] as String? ?? '',
      questionId: map['questionId'] as String? ?? '',
      personId: map['personId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      text: map['text'] as String? ?? '',
      answeredAt: (map['answeredAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dayKey': dayKey,
      'questionId': questionId,
      'personId': personId,
      'authorName': authorName,
      'text': text,
      'answeredAt': answeredAt,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  DailyAnswer copyWith({
    String? dayKey,
    String? questionId,
    String? personId,
    String? authorName,
    String? text,
    int? answeredAt,
    int? updatedAt,
    bool? deleted,
  }) {
    return DailyAnswer(
      id: id,
      dayKey: dayKey ?? this.dayKey,
      questionId: questionId ?? this.questionId,
      personId: personId ?? this.personId,
      authorName: authorName ?? this.authorName,
      text: text ?? this.text,
      answeredAt: answeredAt ?? this.answeredAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
