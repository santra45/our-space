import 'plain_record.dart';

class DailyQuestion {
  const DailyQuestion({required this.id, required this.tone, required this.text});

  final String id;
  final String tone;
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'tone': tone, 'text': text};
}

class QuestionBatch {
  const QuestionBatch({required this.id, required this.questions});

  final String id;
  final List<DailyQuestion> questions;
}

class DailyAnswerEntry {
  DailyAnswerEntry(Map<String, Object?> fields) : fields = Map<String, Object?>.unmodifiable(fields);

  final Map<String, Object?> fields;

  String? get questionId => readString(fields['questionId']);

  String get text => readString(fields['text']) ?? '';

  int get answeredAt => readInt(fields['answeredAt']) ?? 0;

  Map<String, Object?> toJson() => Map<String, Object?>.from(fields);
}

class DailyAnswersRecord extends PlainRecord {
  DailyAnswersRecord(super.fields);

  String? get ownerId => readString(fields['ownerId']);

  String? get month => readString(fields['month']);

  Map<String, DailyAnswerEntry> get answers {
    final value = fields['answers'];
    final out = <String, DailyAnswerEntry>{};
    if (value is Map) {
      value.forEach((day, entry) {
        if (entry is Map) {
          out[day.toString()] = DailyAnswerEntry(entry.map((k, v) => MapEntry(k.toString(), v)));
        }
      });
    }
    return out;
  }
}

class QuestionOfTheDay {
  const QuestionOfTheDay({required this.question, required this.day, required this.index});

  final DailyQuestion question;
  final String day;
  final int index;
}

class DayAnswers {
  const DayAnswers({
    required this.day,
    required this.mine,
    required this.partnerAnswer,
    required this.partnerHasAnswered,
  });

  final String day;
  final DailyAnswerEntry? mine;
  final DailyAnswerEntry? partnerAnswer;
  final bool partnerHasAnswered;
}

class AnsweredDay {
  const AnsweredDay({required this.day, required this.question, required this.mine, required this.theirs});

  final String day;
  final DailyQuestion? question;
  final DailyAnswerEntry mine;
  final DailyAnswerEntry? theirs;
}

class ArchiveDay {
  const ArchiveDay({
    required this.day,
    required this.question,
    required this.mine,
    required this.theirs,
    required this.partnerHasAnswered,
    required this.missed,
  });

  final String day;
  final DailyQuestion? question;
  final DailyAnswerEntry? mine;
  final DailyAnswerEntry? theirs;
  final bool partnerHasAnswered;
  final bool missed;
}
