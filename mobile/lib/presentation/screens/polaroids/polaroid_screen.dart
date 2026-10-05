import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';
import '../../../models/memory.dart';
import '../../../core/crypto/envelope.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/haptics/haptics_service.dart';

class PolaroidScreen extends StatefulWidget {
  const PolaroidScreen({super.key});

  @override
  State<PolaroidScreen> createState() => _PolaroidScreenState();
}

class _PolaroidScreenState extends State<PolaroidScreen> {
  List<Memory> _memories = [];
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    if (keyBytes == null) return;

    final records = await AppDatabase.instance.getActiveRecords('memories');
    final List<Memory> loaded = [];

    for (final r in records) {
      try {
        final imageBlob = r['imageBlob'] as Uint8List?;
        final decrypted = await RecordEnvelope.decryptRecord(
          r,
          keyBytes,
          table: 'memories',
          imageBytes: imageBlob,
        );

        if (!decrypted.isHeaderTampered) {
          loaded.add(Memory.fromMap(decrypted.data, imageBytes: imageBlob));
        }
      } catch (_) {}
    }

    setState(() {
      _memories = loaded;
      _isLoading = false;
    });
  }

  Future<void> _addPhotoDialog() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 85,
    );

    if (pickedFile == null) return;
    final bytes = await pickedFile.readAsBytes();

    final captionController = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('New Memory 📸', style: Theme.of(context).textTheme.headlineSmall),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(bytes, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: captionController,
                decoration: const InputDecoration(labelText: 'Write a caption...'),
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
              final caption = captionController.text.trim();
              final keyBytes = VaultKeyHolder.instance.rawKeyBits;
              if (keyBytes == null) return;

              final memory = Memory(
                id: 'mem-${DateTime.now().millisecondsSinceEpoch}',
                caption: caption,
                date: DateTime.now().toIso8601String().substring(0, 10),
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              );

              final envelope = await RecordEnvelope.encryptRecord(
                memory.toMap(),
                keyBytes,
                table: 'memories',
                imageBytes: bytes,
              );

              await AppDatabase.instance.putEnvelope('memories', envelope, imageBlob: bytes);
              HapticsService.instance.celebration();
              if (ctx.mounted) Navigator.pop(ctx);
              _loadMemories();
            },
            child: const Text('Add Memory 📸'),
          ),
        ],
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
        title: Text('Scrapbook Wall 📸', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPhotoDialog,
        backgroundColor: AppColors.blush500,
        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blush500))
          : _memories.isEmpty
              ? Center(
                  child: Text(
                    'No polaroids pinned yet.\nTap + to add your first photo!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.76,
                  ),
                  itemCount: _memories.length,
                  itemBuilder: (ctx, i) {
                    final m = _memories[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: m.imageBytes != null
                                  ? Image.memory(m.imageBytes!, fit: BoxFit.cover, width: double.infinity)
                                  : Container(
                                      color: AppColors.blush100,
                                      child: const Center(
                                        child: Icon(Icons.broken_image_rounded, color: AppColors.slate400),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            m.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: 18,
                              color: AppColors.slate800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.date,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 10,
                              color: AppColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
