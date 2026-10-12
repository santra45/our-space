import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_theme.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

final List<HapticKind> recordedHaptics = [];

void recordHaptics() {
  recordedHaptics.clear();
  AppHaptics.handler = recordedHaptics.add;
}

Widget host(Widget child, {bool animations = false, bool scaffold = true}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
      child: app!,
    ),
    home: scaffold ? Scaffold(body: Center(child: child)) : child,
  );
}

Future<void> pumpHost(WidgetTester tester, Widget child, {bool animations = false, bool scaffold = true}) async {
  await tester.pumpWidget(host(child, animations: animations, scaffold: scaffold));
  await tester.pump();
}

void usePhoneSize(WidgetTester tester, {double top = 24, double bottom = 16}) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  tester.view.viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  addTearDown(tester.view.reset);
}
