import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/app_colors.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/crypto/backup_crypto.dart';
import '../../../core/haptics/haptics_service.dart';

class SyncHubScreen extends StatefulWidget {
  const SyncHubScreen({super.key});

  @override
  State<SyncHubScreen> createState() => _SyncHubScreenState();
}

class _SyncHubScreenState extends State<SyncHubScreen> {
  bool _isBiometricsEnrolled = false;
  bool _isBiometricsSupported = false;
  final String _localPeerId = 'ourspace-mobile-peer-demo';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final supported = await BiometricService.instance.isBiometricsAvailable();
    final enrolled = await BiometricService.instance.isEnrolled();
    setState(() {
      _isBiometricsSupported = supported;
      _isBiometricsEnrolled = enrolled;
    });
  }

  Future<void> _toggleBiometrics(bool enable) async {
    final keyBytes = VaultKeyHolder.instance.rawKeyBits;
    final salt = VaultKeyHolder.instance.salt;

    if (enable) {
      if (keyBytes != null && salt != null) {
        final success = await BiometricService.instance.enrollBiometrics(
          keyBytes,
          salt: salt,
        );
        if (success) {
          HapticsService.instance.celebration();
          _checkBiometrics();
        }
      }
    } else {
      await BiometricService.instance.disableBiometrics();
      HapticsService.instance.tap();
      _checkBiometrics();
    }
  }

  Future<void> _exportBackup() async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Export Encrypted Backup 🔒', style: Theme.of(context).textTheme.headlineSmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose a passphrase to encrypt your .vault backup file:'),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Backup Passphrase (min 16 chars)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final pass = passwordController.text.trim();
              if (pass.length < 16) return;
              Navigator.pop(ctx);

              final backupJson = await BackupCrypto.exportBackup(pass);
              await Share.share(
                backupJson,
                subject: 'our_space_backup.vault',
              );
              HapticsService.instance.celebration();
            },
            child: const Text('Export & Share'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.single.bytes == null) return;

    final backupJson = String.fromCharCodes(result.files.single.bytes!);
    final passwordController = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Restore from Backup 📥', style: Theme.of(context).textTheme.headlineSmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the passphrase used when creating this .vault backup:'),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Backup Passphrase'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final pass = passwordController.text.trim();
              if (pass.isEmpty) return;
              Navigator.pop(ctx);

              try {
                final count = await BackupCrypto.importBackup(backupJson, pass);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Successfully merged $count records from backup! 💕')),
                  );
                }
                HapticsService.instance.celebration();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to restore backup: $e')),
                  );
                }
              }
            },
            child: const Text('Restore & Merge'),
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
        title: Text('Sync & Security 🛡️', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('Direct Phone-to-Phone Pairing ⚡', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Point your partner\'s phone camera at this QR code to connect directly over WebRTC.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.blush200, width: 2),
                    ),
                    child: QrImageView(
                      data: 'our-space://pair?peerId=$_localPeerId',
                      version: QrVersions.auto,
                      size: 180,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your Code: $_localPeerId',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (_isBiometricsSupported) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.blush100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fingerprint_rounded, color: AppColors.blush500),
                  ),
                  title: Text('Open with a touch', style: theme.textTheme.titleMedium),
                  subtitle: Text(
                    'Seals your key behind this phone\'s biometric sensor',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                  ),
                  value: _isBiometricsEnrolled,
                  onChanged: _toggleBiometrics,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Encrypted Backups 💾', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Save your memories to an encrypted .vault file that only your password can open.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.slate500),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportBackup,
                          icon: const Icon(Icons.upload_file_rounded, color: AppColors.blush500),
                          label: const Text('Export .vault'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importBackup,
                          icon: const Icon(Icons.download_rounded, color: AppColors.lavender600),
                          label: const Text('Restore .vault'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
