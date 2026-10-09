import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/engine.dart';
import 'presentation/home_shell.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/space_scope.dart';
import 'presentation/theme/app_colors.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/vault_gate.dart';
import 'presentation/widgets/our_feedback.dart';

typedef VaultGateBuilder = Widget Function(BuildContext context, Widget shell);

typedef SpaceOpener = Future<OurSpace> Function();

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

Future<OurSpace> openOurSpace() => OurSpace.open();

Widget vaultGate(BuildContext context, Widget shell) => VaultGate(shell: shell);

class OurSpaceApp extends StatefulWidget {
  const OurSpaceApp({super.key, this.openSpace = openOurSpace, this.gate = vaultGate, this.shell});

  final SpaceOpener openSpace;
  final VaultGateBuilder gate;
  final Widget? shell;

  @override
  State<OurSpaceApp> createState() => _OurSpaceAppState();
}

class _OurSpaceAppState extends State<OurSpaceApp> {
  OurSpace? _space;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    if (_failed) setState(() => _failed = false);
    try {
      final space = await widget.openSpace();
      if (!mounted || attempt != _attempt) {
        await space.close();
        return;
      }
      setState(() => _space = space);
    } catch (_) {
      if (mounted && attempt == _attempt) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _attempt++;
    final space = _space;
    _space = null;
    if (space != null) unawaited(space.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Our Space 💕',
      color: AppColors.blush100,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, navigator) {
        final space = _space;
        if (space == null) return LockScreenBoot(failed: _failed, onRetry: _open);
        return SpaceScope(
          space: space,
          child: Stack(
            fit: StackFit.expand,
            children: [navigator!, const VaultWarningBanner()],
          ),
        );
      },
      home: Builder(builder: (context) => widget.gate(context, widget.shell ?? const HomeShell())),
    );
  }
}
