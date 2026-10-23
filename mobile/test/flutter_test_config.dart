import 'dart:async';

import 'package:our_space_mobile/presentation/app_shell.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SkyShell.warmTabs = false;
  await testMain();
}
