import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../../data/daily_questions_data.dart';
import '../../../models/daily_answer.dart';
import '../../../core/crypto/envelope.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/haptics/haptics_service.dart';

class DailyQuestionScreen extends StatefulWidget {
  const DailyQuestionScreen({super.key});

  @override
  State<DailyQuestionScreen> createState() => _DailyQuestionScreenState();
}

class _DailyQuestionScreenState extends State<DailyQuestionScreen> {
  final TextEditingController _answerController = TextEditingController();
  bool _isLoading = true;

  DailyQuestionItem? _todayQuestion;
  DailyAnswer? _myAnswer;
  DailyAnswer? _partnerAnswer;

  late String _dayKey;

  @override
  void initState() {
    super.initState();
    _dayKey = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    _loadDailyState();
  }

  Future<void> _loadDailyState() async {
    final now = DateTime.now().toUtc();
    final daysSinceEpoch = now.millisecondsSinceEpoch ~/ (1000 * 60 * 60 * 24);
    final questionIndex = daysSinceEpoch % allQuestions.length;
    _todayQuestion = allQuestions[questionIndex];

    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes != null) {
      final records = await AppDatabase.instance.getActiveRecords('dailyAnswers');
      DailyAnswer? myAns;
      DailyAnswer? partAns;

      for (final r in records) {
        try {
          final decrypted = await RecordEnvelope.decryptRecord(r, keyBytes, table: 'dailyAnswers');
          if (!decrypted.isHeaderTampered) {
            final ans = DailyAnswer.fromMap(decrypted.data);
            if (ans.dayKey == _dayKey) {
              if (ans.authorName == 'Me') {
                myAns = ans;
              } else {
                partAns = ans;
              }
            }
          }
        } catch (_) {}
      }

      _myAnswer = myAns;
      _partnerAnswer = partAns;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _submitMyAnswer() async {
    final text = _answerController.text.trim();
    if (text.isEmpty) return;

    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final myAns = DailyAnswer(
      id: 'ans-$_dayKey-me',
      dayKey: _dayKey,
      questionId: _todayQuestion!.id,
      personId: 'me',
      authorName: 'Me',
      text: text,
      answeredAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final envelope = await RecordEnvelope.encryptRecord(
      myAns.toMap(),
      keyBytes,
      table: 'dailyAnswers',
    );

    await AppDatabase.instance.putEnvelope('dailyAnswers', envelope);
    HapticsService.instance.celebration();

    _answerController.clear();
    _loadDailyState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.blush50,
        body: Center(child: CircularProgressIndicator(color: AppColors.blush500)),
      );
    }

    final hasBothAnswered = _myAnswer != null && _partnerAnswer != null;
    final hasIAnswered = _myAnswer != null;

    return Scaffold(
      backgroundColor: AppColors.blush50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Daily Question 💬', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.blush100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'TODAY’S QUESTION',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.blush600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _todayQuestion?.text ?? '',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 26,
                        color: AppColors.slate900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            if (!hasIAnswered) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Your Answer', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Neither answer shows until both of you have written one.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _answerController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Speak from the heart...',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _submitMyAnswer,
                        child: const Text('Submit My Answer 💕'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.matcha300, size: 20),
                          const SizedBox(width: 8),
                          Text('You answered:', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _myAnswer!.text,
                        style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                color: hasBothAnswered ? Colors.white : AppColors.lavender50,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasBothAnswered) ...[
                        Row(
                          children: [
                            const Icon(Icons.favorite_rounded, color: AppColors.blush500, size: 20),
                            const SizedBox(width: 8),
                            Text('${_partnerAnswer!.authorName} answered:', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _partnerAnswer!.text,
                          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
                        ),
                      ] else ...[
                        const Icon(Icons.lock_outline_rounded, color: AppColors.lavender600, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'Waiting for your partner 💕',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(color: AppColors.lavender700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Their answer will automatically appear as soon as they open the app and write theirs.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
