class DateIdea {
  final String id;
  final String title;
  final String description;
  final String category;
  final bool completed;
  final int updatedAt;
  final bool deleted;

  DateIdea({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'romantic',
    this.completed = false,
    required this.updatedAt,
    this.deleted = false,
  });

  factory DateIdea.fromMap(Map<String, dynamic> map) {
    return DateIdea(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'romantic',
      completed: map['completed'] == true,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'completed': completed,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  DateIdea copyWith({
    String? title,
    String? description,
    String? category,
    bool? completed,
    int? updatedAt,
    bool? deleted,
  }) {
    return DateIdea(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
