import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/lucide_icon.dart';

import 'harness.dart';

Set<String> _webIconNames() {
  final names = <String>{};
  final block = RegExp(r"import\s*\{([^}]*)\}\s*from\s*'lucide-react'");
  for (final file in Directory('../src').listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.jsx') && !file.path.endsWith('.js')) continue;
    for (final m in block.allMatches(file.readAsStringSync())) {
      for (final raw in m.group(1)!.split(',')) {
        final name = raw.trim().split(RegExp(r'\s+as\s+')).first.trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
  }
  return names;
}

String _kebab(String name) => name
    .replaceAllMapped(RegExp(r'([a-z])([A-Z0-9])'), (m) => '${m[1]}-${m[2]}')
    .replaceAllMapped(RegExp(r'([0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
    .toLowerCase();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every lucide icon the web imports ships as an SVG asset', () {
    final bundled = AppIcons.all.map((i) => i.name).toSet();
    final web = _webIconNames();
    expect(web, isNotEmpty);
    for (final name in web) {
      expect(bundled, contains(_kebab(name)), reason: name);
    }
  });

  test('every icon asset loads from the bundle as a lucide 24px stroke SVG', () async {
    for (final icon in AppIcons.all) {
      final svg = await rootBundle.loadString(icon.asset);
      expect(svg, contains('viewBox="0 0 24 24"'), reason: icon.name);
      expect(svg, contains('stroke="currentColor"'), reason: icon.name);
      expect(svg, contains('fill="none"'), reason: icon.name);
    }
  });

  test('illustration assets are SVG, not bitmaps', () {
    final files = Directory('assets').listSync(recursive: true).whereType<File>().map((f) => f.path.toLowerCase());
    expect(files.where((p) => p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.webp')), isEmpty);
    expect(files.where((p) => p.endsWith('.svg')).length, greaterThan(AppIcons.all.length));
  });

  test('fill and stroke overrides only touch the root svg element', () {
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">\n'
        '  <circle cx="1" cy="1" r=".5" fill="currentColor" stroke-width="2" />\n'
        '</svg>';
    final out = applyLucideOverrides(source, fill: AppColors.blush200, strokeWidth: 3);
    expect(out, contains('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#ffd1dc" fill-opacity="1" stroke="currentColor" stroke-width="3">'));
    expect(out, contains('<circle cx="1" cy="1" r=".5" fill="currentColor" stroke-width="2" />'));
    expect(applyLucideOverrides(source), source);
    final translucent = applyLucideOverrides(source, fill: AppColors.white.withValues(alpha: 0.5));
    expect(translucent, contains('fill="#ffffff" fill-opacity="0.5"'));
  });

  testWidgets('LucideIcon renders an SVG picture at the requested size', (tester) async {
    await pumpHost(tester, const LucideIcon(AppIcons.heart, size: 20, color: AppColors.blush500, fill: AppColors.blush200));
    final box = tester.getSize(find.byType(LucideIcon));
    expect(box, const Size(20, 20));
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = picture.bytesLoader as LucideSvgLoader;
    expect(loader.assetName, 'assets/svg/icons/heart.svg');
    expect(loader.fill, AppColors.blush200);
    expect(loader.theme?.currentColor, AppColors.blush500);
  });

  testWidgets('LucideIcon falls back to the ambient text colour', (tester) async {
    await pumpHost(
      tester,
      const DefaultTextStyle(style: TextStyle(color: AppColors.slate400), child: LucideIcon(AppIcons.lock, size: 14)),
    );
    final loader = tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader as LucideSvgLoader;
    expect(loader.theme?.currentColor, AppColors.slate400);
  });
}
