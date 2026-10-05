import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/vault_key.dart';
import '../../../core/biometrics/biometric_service.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/haptics/haptics_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isFirstTime = false;
  bool _isLoading = true;
  bool _hasBiometrics = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkVaultState();
  }

  Future<void> _checkVaultState() async {
    final meta = await AppDatabase.instance.getVaultMeta();
    final biometricsEnrolled = await BiometricService.instance.isEnrolled();

    setState(() {
      _isFirstTime = meta == null;
      _hasBiometrics = biometricsEnrolled;
      _isLoading = false;
    });

    if (biometricsEnrolled) {
      _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    final success = await BiometricService.instance.unlockWithBiometrics();
    if (success && mounted) {
      HapticsService.instance.heartbeat();
      widget.onUnlocked();
    }
  }

  Future<void> _handleUnlockOrSetup() async {
    final passphrase = _passphraseController.text;
    if (passphrase.trim().length < 16) {
      setState(() => _errorMessage = 'Passphrase must be at least 16 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isFirstTime) {
        if (passphrase != _confirmController.text) {
          setState(() {
            _errorMessage = 'Passphrases do not match.';
            _isLoading = false;
          });
          return;
        }

        // Initialize new vault
        final salt = CryptoEngine.instance.generateSalt();
        final keyBytes = await CryptoEngine.instance.deriveKeyFromPassphrase(passphrase, salt);
        final canary = await CryptoEngine.instance.createCanary(keyBytes);

        await AppDatabase.instance.saveVaultMeta({
          'salt': salt,
          'canary': canary['canary'],
          'canaryIv': canary['canaryIv'],
        });

        VaultKeyHolder.instance.setKey(keyBytes, salt: salt);
        HapticsService.instance.celebration();
        widget.onUnlocked();
      } else {
        // Unlock existing vault
        final meta = await AppDatabase.instance.getVaultMeta();
        if (meta == null) throw Exception('Vault metadata missing');

        final salt = meta['salt'] as String;
        final iterations = (meta['kdfIterations'] as num?)?.toInt() ?? 600000;

        final keyBytes = await CryptoEngine.instance.deriveKeyFromPassphrase(
          passphrase,
          salt,
          iterations: iterations,
        );

        final config = await CryptoEngine.instance.readCanary(keyBytes, meta);
        if (config == null) {
          setState(() {
            _errorMessage = 'Incorrect passphrase. Please try again.';
            _isLoading = false;
          });
          return;
        }

        VaultKeyHolder.instance.setKey(keyBytes, salt: salt, iterations: iterations);
        HapticsService.instance.heartbeat();
        widget.onUnlocked();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.blush50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Heart Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.blush100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.blush500,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Our Space 💕',
                  style: theme.textTheme.displayLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _isFirstTime
                      ? 'Create your private shared sanctuary for two'
                      : 'Enter your shared secret passphrase',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),

                // Biometrics shortcut button
                if (!_isFirstTime && _hasBiometrics) ...[
                  OutlinedButton.icon(
                    onPressed: _tryBiometricUnlock,
                    icon: const Icon(Icons.fingerprint_rounded, color: AppColors.blush500, size: 26),
                    label: Text(
                      'Open with Biometrics',
                      style: theme.textTheme.titleMedium?.copyWith(color: AppColors.blush500),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      side: const BorderSide(color: AppColors.blush300, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.blush200)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR PASSPHRASE', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11)),
                      ),
                      const Expanded(child: Divider(color: AppColors.blush200)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Passphrase Input
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isFirstTime ? 'Passphrase (min 16 characters)' : 'Passphrase',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.slate400),
                  ),
                ),

                if (_isFirstTime) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm passphrase',
                      prefixIcon: Icon(Icons.check_circle_outline_rounded, color: AppColors.slate400),
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleUnlockOrSetup,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(_isFirstTime ? 'Create Private Vault' : 'Open Vault 💕'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
