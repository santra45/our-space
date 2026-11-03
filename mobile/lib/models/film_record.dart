import 'plain_record.dart';

class FilmRecord extends PlainRecord {
  FilmRecord(super.fields);

  String get title => readString(fields['title']) ?? '';

  int get watchedAt => readInt(fields['watchedAt']) ?? 0;

  int get togetherMs => readInt(fields['togetherMs']) ?? 0;
}

class FilmLineRecord extends PlainRecord {
  FilmLineRecord(super.fields);

  String get film => readString(fields['film']) ?? '';

  String get text => readString(fields['text']) ?? '';

  String get by => readString(fields['by']) ?? '';

  int get posMs => readInt(fields['posMs']) ?? 0;

  int get at => readInt(fields['at']) ?? 0;
}
