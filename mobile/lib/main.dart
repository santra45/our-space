import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/crypto/vault_key.dart';
import 'presentation/app_shell.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/theme/app_colors.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/widgets/our_feedback.dart';

typedef VaultGateBuilder = Widget Function(BuildContext context, Widget shell);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppChrome();
  runApp(const OurSpaceApp());
}

void configureAppChrome() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  LicenseRegistry.addLicense(bundledLicenses);
  if (!kDebugMode) {
    ErrorWidget.builder = (details) => const Material(type: MaterialType.transparency, child: OurErrorCard());
  }
}

Stream<LicenseEntry> bundledLicenses() async* {
  yield LicenseEntryWithLineBreaks(['Caveat'], await rootBundle.loadString('assets/fonts/caveat/OFL.txt'));
  yield LicenseEntryWithLineBreaks(['lucide'], await rootBundle.loadString('assets/svg/icons/LICENSE.txt'));
}

class OurSpaceApp extends StatelessWidget {
  const OurSpaceApp({super.key, this.gate = legacyVaultGate, this.shell});

  final VaultGateBuilder gate;
  final Widget? shell;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Our Space 💕',
      color: AppColors.blush100,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Builder(builder: (context) => gate(context, shell ?? const AppShell())),
    );
  }
}

Widget openVaultGate(BuildContext context, Widget shell) => shell;

Widget legacyVaultGate(BuildContext context, Widget shell) => LegacyVaultGate(shell: shell);

class LegacyVaultGate extends StatefulWidget {
  const LegacyVaultGate({super.key, required this.shell});

  final Widget shell;

  @override
  State<LegacyVaultGate> createState() => _LegacyVaultGateState();
}

class _LegacyVaultGateState extends State<LegacyVaultGate> {
  void _onVaultChanged(bool _) {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    VaultKeyHolder.instance.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    VaultKeyHolder.instance.removeListener(_onVaultChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!VaultKeyHolder.instance.isUnlocked) {
      return LockScreen(onUnlocked: () => setState(() {}));
    }
    return ShellActions(onLock: VaultKeyHolder.instance.lock, child: widget.shell);
  }
}
