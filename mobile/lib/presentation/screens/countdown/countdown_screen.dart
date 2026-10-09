import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../../models/milestone.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/crypto/envelope.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/haptics/haptics_service.dart';

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  List<Milestone> _milestones = [];
  bool _isLoading = true;
  final String _coupleStartDate = '2024-01-01';

  @override
  void initState() {
    super.initState();
    _loadMilestones();
  }

  Future<void> _loadMilestones() async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final records = await AppDatabase.instance.getActiveRecords('milestones');
    final List<Milestone> items = [];

    for (final r in records) {
      try {
        final decrypted = await RecordEnvelope.decryptRecord(r, keyBytes, table: 'milestones');
        if (!decrypted.isHeaderTampered) {
          items.add(Milestone.fromMap(decrypted.data));
        }
      } catch (_) {}
    }

    setState(() {
      _milestones = items;
      _isLoading = false;
    });
  }

  int _calculateDaysTogether() {
    try {
      final start = DateTime.parse(_coupleStartDate);
      final now = DateTime.now();
      return now.difference(start).inDays;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _addMilestoneDialog() async {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Add a Milestone 💕', style: Theme.of(context).textTheme.headlineSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Milestone Title (e.g. First trip)'),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded, color: AppColors.blush500),
                title: Text(DateFormat('MMMM d, yyyy').format(selectedDate)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                final keyBytes = VaultKeyHolder.instance.rawKeyBits;
                if (keyBytes == null) return;

                final newMilestone = Milestone(
                  id: 'ms-${DateTime.now().millisecondsSinceEpoch}',
                  title: title,
                  date: DateFormat('yyyy-MM-dd').format(selectedDate),
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );

                final envelope = await RecordEnvelope.encryptRecord(
                  newMilestone.toMap(),
                  keyBytes,
                  table: 'milestones',
                );

                await AppDatabase.instance.putEnvelope('milestones', envelope);
                HapticsService.instance.tap();
                if (ctx.mounted) Navigator.pop(ctx);
                _loadMilestones();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _calculateDaysTogether();

    return Scaffold(
      backgroundColor: AppColors.blush50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Our Love Story 💕', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blush500))
          : RefreshIndicator(
              onRefresh: _loadMilestones,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      child: Column(
                        children: [
                          const Icon(Icons.favorite_rounded, color: AppColors.blush500, size: 36),
                          const SizedBox(height: 12),
                          Text(
                            '$days Days',
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: AppColors.blush600,
                              fontSize: 48,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'and countless beautiful memories together',
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Milestones', style: theme.textTheme.titleMedium),
                      IconButton(
                        onPressed: _addMilestoneDialog,
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.blush500),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_milestones.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No milestones yet. Tap + to add your first one!',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._milestones.map((m) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.blush100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.star_rounded, color: AppColors.blush500),
                          ),
                          title: Text(m.title, style: theme.textTheme.titleMedium),
                          subtitle: Text(m.date, style: theme.textTheme.bodyMedium),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
