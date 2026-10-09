import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../../models/letter.dart';
import '../../../core/crypto/timelock.dart';
import '../../../core/crypto/envelope.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/haptics/haptics_service.dart';

class SecretCapsuleScreen extends StatefulWidget {
  const SecretCapsuleScreen({super.key});

  @override
  State<SecretCapsuleScreen> createState() => _SecretCapsuleScreenState();
}

class _SecretCapsuleScreenState extends State<SecretCapsuleScreen> {
  List<Letter> _letters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLetters();
  }

  Future<void> _loadLetters() async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final records = await AppDatabase.instance.getActiveRecords('letters');
    final List<Letter> items = [];

    for (final r in records) {
      try {
        final decrypted = await RecordEnvelope.decryptRecord(r, keyBytes, table: 'letters');
        if (!decrypted.isHeaderTampered) {
          items.add(Letter.fromMap(decrypted.data));
        }
      } catch (_) {}
    }

    setState(() {
      _letters = items;
      _isLoading = false;
    });
  }

  Future<void> _composeLetterDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    DateTime? unlockDate;
    bool isTimeLocked = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Write a Letter 💌', style: Theme.of(context).textTheme.headlineSmall),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title / Subject'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bodyController,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Dear love...'),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seal until future date 🔒'),
                  value: isTimeLocked,
                  onChanged: (val) {
                    setDialogState(() {
                      isTimeLocked = val;
                      if (val && unlockDate == null) {
                        unlockDate = DateTime.now().add(const Duration(days: 30));
                      }
                    });
                  },
                ),
                if (isTimeLocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_clock_rounded, color: AppColors.blush500),
                    title: Text(DateFormat('MMMM d, yyyy').format(unlockDate!)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: unlockDate!,
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => unlockDate = picked);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final body = bodyController.text.trim();
                if (title.isEmpty || body.isEmpty) return;

                final keyBytes = VaultKeyHolder.instance.rawKeyBits;
                if (keyBytes == null) return;

                final id = 'let-${DateTime.now().millisecondsSinceEpoch}';
                String finalBody = body;
                Map<String, dynamic>? sealedPayload;
                String? finalUnlockDate;

                if (isTimeLocked && unlockDate != null) {
                  finalUnlockDate = DateFormat('yyyy-MM-dd').format(unlockDate!);
                  sealedPayload = await TimeLockEngine.sealTimeLocked(
                    body,
                    finalUnlockDate,
                    keyBytes,
                    context: id,
                  );
                  finalBody = '';
                }

                final letter = Letter(
                  id: id,
                  title: title,
                  body: finalBody,
                  authorName: 'Me',
                  unlockDate: finalUnlockDate,
                  isSealed: isTimeLocked,
                  timeLockPayload: sealedPayload,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );

                final envelope = await RecordEnvelope.encryptRecord(
                  letter.toMap(),
                  keyBytes,
                  table: 'letters',
                );

                await AppDatabase.instance.putEnvelope('letters', envelope);
                HapticsService.instance.celebration();
                if (ctx.mounted) Navigator.pop(ctx);
                _loadLetters();
              },
              child: const Text('Seal & Save 💌'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLetter(Letter letter) async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    String body = letter.body;

    if (letter.isSealed && letter.timeLockPayload != null) {
      if (!TimeLockEngine.isTimeLockOpen(letter.unlockDate)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('This letter is cryptographically sealed until ${letter.unlockDate} 🔒'),
            backgroundColor: AppColors.slate800,
          ),
        );
        return;
      }

      try {
        body = await TimeLockEngine.unsealTimeLocked(
          letter.timeLockPayload!,
          keyBytes,
          context: letter.id,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unseal letter: $e')),
        );
        return;
      }
    }

    if (!mounted) return;
    HapticsService.instance.heartbeat();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: AppColors.cream50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.slate200,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              letter.title,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'From ${letter.authorName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.slate400),
            ),
            const Divider(height: 32, color: AppColors.blush200),
            Text(
              body,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.blush50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Secret Capsule 💌', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _composeLetterDialog,
        backgroundColor: AppColors.blush500,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blush500))
          : _letters.isEmpty
              ? Center(
                  child: Text(
                    'No letters sealed yet.\nWrite your first love letter!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _letters.length,
                  itemBuilder: (ctx, i) {
                    final l = _letters[i];
                    final isLocked = l.isSealed && !TimeLockEngine.isTimeLockOpen(l.unlockDate);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: ListTile(
                        onTap: () => _openLetter(l),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLocked ? AppColors.lavender100 : AppColors.blush100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isLocked ? Icons.lock_clock_rounded : Icons.mail_outline_rounded,
                            color: isLocked ? AppColors.lavender600 : AppColors.blush500,
                          ),
                        ),
                        title: Text(l.title, style: theme.textTheme.titleMedium),
                        subtitle: Text(
                          isLocked ? 'Sealed until ${l.unlockDate} 🔒' : 'From ${l.authorName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isLocked ? AppColors.lavender600 : AppColors.slate500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
