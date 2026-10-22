import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/engine.dart';
import 'presentation/deep_links.dart';
import 'presentation/home_shell.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/space_scope.dart';
import 'presentation/sky/sky.dart';
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
  yield LicenseEntryWithLineBreaks(['Bodoni Moda'], await rootBundle.loadString('assets/fonts/bodoni_moda/OFL.txt'));
  yield LicenseEntryWithLineBreaks(['DM Sans'], await rootBundle.loadString('assets/fonts/dm_sans/OFL.txt'));
  yield LicenseEntryWithLineBreaks(['lucide'], await rootBundle.loadString('assets/svg/icons/LICENSE.txt'));
}

Future<OurSpace> openOurSpace() async => OurSpace.open(pushPlatform: await FirebasePushPlatform.start());

Widget vaultGate(BuildContext context, Widget shell) => InviteLinkGate(shell: shell);

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
  SkyModeController _sky = SkyModeController();

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
      final previous = _sky;
      setState(() {
        _space = space;
        _sky = SkyModeController(settings: space.store.settings);
      });
      previous.dispose();
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
    _sky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sky = _sky;
    return ListenableBuilder(
      listenable: sky,
      builder: (context, _) => MaterialApp(
        title: 'Our Space',
        color: sky.tokens.page,
        debugShowCheckedModeBanner: false,
        theme: SkyThemes.legacy(sky.tokens),
        themeAnimationDuration: SkyMotion.dayNight,
        themeAnimationCurve: Curves.easeInOut,
        builder: (context, navigator) {
          final space = _space;
          if (space == null) {
            return SkyModeScope(
              controller: sky,
              child: LockScreenBoot(failed: _failed, onRetry: _open),
            );
          }
          return SkyModeScope(
            controller: sky,
            child: SpaceScope(
              space: space,
              child: Stack(fit: StackFit.expand, children: [navigator!, const VaultWarningBanner()]),
            ),
          );
        },
        home: Builder(builder: (context) => widget.gate(context, widget.shell ?? const HomeShell())),
      ),
    );
  }
}
