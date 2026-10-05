class BucketItem {
  final String id;
  final String text;
  final String category;
  final bool completed;
  final int? completedAt;
  final String? completedBy;
  final int updatedAt;
  final bool deleted;

  BucketItem({
    required this.id,
    required this.text,
    this.category = 'travel',
    this.completed = false,
    this.completedAt,
    this.completedBy,
    required this.updatedAt,
    this.deleted = false,
  });

  factory BucketItem.fromMap(Map<String, dynamic> map) {
    return BucketItem(
      id: map['id'] as String,
      text: map['text'] as String? ?? '',
      category: map['category'] as String? ?? 'travel',
      completed: map['completed'] == true,
      completedAt: (map['completedAt'] as num?)?.toInt(),
      completedBy: map['completedBy'] as String?,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'category': category,
      'completed': completed,
      'completedAt': completedAt,
      'completedBy': completedBy,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  BucketItem copyWith({
    String? text,
    String? category,
    bool? completed,
    int? completedAt,
    String? completedBy,
    int? updatedAt,
    bool? deleted,
  }) {
    return BucketItem(
      id: id,
      text: text ?? this.text,
      category: category ?? this.category,
      completed: completed ?? this.completed,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
