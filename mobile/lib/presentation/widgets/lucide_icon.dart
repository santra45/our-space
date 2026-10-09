import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

@immutable
class LucideIconData {
  const LucideIconData(this.name);

  final String name;

  String get asset => 'assets/svg/icons/$name.svg';

  @override
  bool operator ==(Object other) => other is LucideIconData && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'LucideIconData($name)';
}

String applyLucideOverrides(String svg, {Color? fill, double? strokeWidth}) {
  final start = svg.indexOf('<svg');
  if (start < 0) return svg;
  final end = svg.indexOf('>', start);
  if (end < 0) return svg;
  var root = svg.substring(start, end);
  if (fill != null) {
    final rgb = (fill.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final paint = 'fill="#$rgb" fill-opacity="${_number(fill.a)}"';
    root = root.contains('fill="none"') ? root.replaceFirst('fill="none"', paint) : '$root $paint';
  }
  if (strokeWidth != null) {
    final width = 'stroke-width="${_number(strokeWidth)}"';
    root = root.contains(RegExp(r'stroke-width="[^"]*"'))
        ? root.replaceFirst(RegExp(r'stroke-width="[^"]*"'), width)
        : '$root $width';
  }
  return svg.substring(0, start) + root + svg.substring(end);
}

String _number(double value) {
  final rounded = double.parse(value.toStringAsFixed(4));
  return rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toString();
}

@immutable
class LucideSvgLoader extends SvgLoader<ByteData> {
  const LucideSvgLoader(
    this.assetName, {
    this.fill,
    this.strokeWidth,
    this.assetBundle,
    super.theme,
  });

  final String assetName;
  final Color? fill;
  final double? strokeWidth;
  final AssetBundle? assetBundle;

  AssetBundle _resolveBundle(BuildContext? context) {
    if (assetBundle != null) return assetBundle!;
    if (context != null) return DefaultAssetBundle.of(context);
    return rootBundle;
  }

  @override
  Future<ByteData?> prepareMessage(BuildContext? context) => _resolveBundle(context).load(assetName);

  @override
  String provideSvg(ByteData? message) {
    final text = utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
    return applyLucideOverrides(text, fill: fill, strokeWidth: strokeWidth);
  }

  @override
  SvgCacheKey cacheKey(BuildContext? context) {
    return SvgCacheKey(
      keyData: (assetName, fill?.toARGB32(), strokeWidth, _resolveBundle(context)),
      theme: getTheme(context),
      colorMapper: colorMapper,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LucideSvgLoader &&
        other.assetName == assetName &&
        other.fill == fill &&
        other.strokeWidth == strokeWidth &&
        other.assetBundle == assetBundle &&
        other.theme == theme;
  }

  @override
  int get hashCode => Object.hash(assetName, fill, strokeWidth, assetBundle, theme);
}

class LucideIcon extends StatelessWidget {
  const LucideIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.fill,
    this.strokeWidth,
    this.semanticLabel,
  });

  final LucideIconData icon;
  final double size;
  final Color? color;
  final Color? fill;
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF1E293B);
    final picture = SvgPicture(
      LucideSvgLoader(
        icon.asset,
        fill: fill,
        strokeWidth: strokeWidth,
        theme: SvgTheme(currentColor: resolved),
      ),
      width: size,
      height: size,
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
    return SizedBox(width: size, height: size, child: picture);
  }
}
