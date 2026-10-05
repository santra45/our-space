class Milestone {
  final String id;
  final String title;
  final String date;
  final String category;
  final bool isAnniversary;
  final int updatedAt;
  final bool deleted;

  Milestone({
    required this.id,
    required this.title,
    required this.date,
    this.category = 'relationship',
    this.isAnniversary = false,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Milestone.fromMap(Map<String, dynamic> map) {
    return Milestone(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      date: map['date'] as String? ?? '',
      category: map['category'] as String? ?? 'relationship',
      isAnniversary: map['isAnniversary'] == true,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'category': category,
      'isAnniversary': isAnniversary,
      'updatedAt': updatedAt,
      'deleted': deleted,
    };
  }

  Milestone copyWith({
    String? title,
    String? date,
    String? category,
    bool? isAnniversary,
    int? updatedAt,
    bool? deleted,
  }) {
    return Milestone(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      category: category ?? this.category,
      isAnniversary: isAnniversary ?? this.isAnniversary,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
