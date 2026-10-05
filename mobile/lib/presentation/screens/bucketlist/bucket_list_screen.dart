import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../../models/bucket_item.dart';
import '../../../core/crypto/envelope.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/haptics/haptics_service.dart';

class BucketListScreen extends StatefulWidget {
  const BucketListScreen({super.key});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen> {
  List<BucketItem> _items = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';

  final List<String> _categories = ['all', 'travel', 'food', 'date', 'cozy'];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final records = await AppDatabase.instance.getActiveRecords('bucketList');
    final List<BucketItem> loaded = [];

    for (final r in records) {
      try {
        final decrypted = await RecordEnvelope.decryptRecord(r, keyBytes, table: 'bucketList');
        if (!decrypted.isHeaderTampered) {
          loaded.add(BucketItem.fromMap(decrypted.data));
        }
      } catch (_) {}
    }

    setState(() {
      _items = loaded;
      _isLoading = false;
    });
  }

  Future<void> _toggleItem(BucketItem item) async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final updated = item.copyWith(
      completed: !item.completed,
      completedAt: !item.completed ? DateTime.now().millisecondsSinceEpoch : null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final envelope = await RecordEnvelope.encryptRecord(
      updated.toMap(),
      keyBytes,
      table: 'bucketList',
    );

    await AppDatabase.instance.putEnvelope('bucketList', envelope);
    if (!item.completed) {
      HapticsService.instance.celebration();
    } else {
      HapticsService.instance.tap();
    }

    _loadItems();
  }

  Future<void> _addItemDialog() async {
    final textController = TextEditingController();
    String category = 'travel';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Add a Dream ✨', style: Theme.of(context).textTheme.headlineSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(labelText: 'What should we do together?'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'travel', child: Text('✈️ Travel')),
                  DropdownMenuItem(value: 'food', child: Text('🍜 Food & Dining')),
                  DropdownMenuItem(value: 'date', child: Text('🕯️ Date Night')),
                  DropdownMenuItem(value: 'cozy', child: Text('☕ Cozy Times')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => category = val);
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
                final text = textController.text.trim();
                if (text.isEmpty) return;

                final keyBytes = VaultKeyHolder.instance.rawKeyBits;
                if (keyBytes == null) return;

                final newItem = BucketItem(
                  id: 'bkt-${DateTime.now().millisecondsSinceEpoch}',
                  text: text,
                  category: category,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );

                final envelope = await RecordEnvelope.encryptRecord(
                  newItem.toMap(),
                  keyBytes,
                  table: 'bucketList',
                );

                await AppDatabase.instance.putEnvelope('bucketList', envelope);
                HapticsService.instance.tap();
                if (ctx.mounted) Navigator.pop(ctx);
                _loadItems();
              },
              child: const Text('Add to List ✨'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _selectedCategory == 'all'
        ? _items
        : _items.where((i) => i.category == _selectedCategory).toList();

    final completedCount = _items.where((i) => i.completed).length;
    final totalCount = _items.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: AppColors.blush50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Shared Bucket List ✨', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItemDialog,
        backgroundColor: AppColors.blush500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blush500))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Progress Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Together Dreams', style: theme.textTheme.titleMedium),
                            Text(
                              '$completedCount / $totalCount done',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.blush600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: AppColors.blush100,
                            valueColor: const AlwaysStoppedAnimation(AppColors.blush500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Category Chips
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat.toUpperCase()),
                        selected: isSelected,
                        selectedColor: AppColors.blush500,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.slate700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _selectedCategory = cat);
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                if (filtered.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          'No dreams in this category yet.\nTap + to add one!',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                else
                  ...filtered.map((item) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => _toggleItem(item),
                        leading: Checkbox(
                          value: item.completed,
                          activeColor: AppColors.blush500,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          onChanged: (_) => _toggleItem(item),
                        ),
                        title: Text(
                          item.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: item.completed ? TextDecoration.lineThrough : null,
                            color: item.completed ? AppColors.slate400 : AppColors.slate800,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
