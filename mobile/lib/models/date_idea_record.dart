import 'plain_record.dart';

class DateIdea {
  const DateIdea({required this.id, required this.title, required this.category, required this.desc});

  final String id;
  final String title;
  final String category;
  final String desc;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'category': category, 'desc': desc};
}

class DateIdeaCategory {
  const DateIdeaCategory({required this.id, required this.label});

  final String id;
  final String label;
}

class RouletteStateRecord extends PlainRecord {
  RouletteStateRecord(super.fields);

  static const String recordId = 'roulette-current';

  String? get ideaId => readString(fields['ideaId']);

  String? get category => readString(fields['category']);

  bool get revealed => fields['revealed'] == true;
}
