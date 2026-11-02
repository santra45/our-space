import 'plain_record.dart';

class FilmRecord extends PlainRecord {
  FilmRecord(super.fields);

  String get title => readString(fields['title']) ?? '';

  int get watchedAt => readInt(fields['watchedAt']) ?? 0;

  int get togetherMs => readInt(fields['togetherMs']) ?? 0;
}
