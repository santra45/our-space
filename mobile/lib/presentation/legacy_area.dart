import 'package:flutter/material.dart';

import 'sky/sky.dart';
import 'theme/app_gradients.dart';
import 'theme/app_theme.dart';

class LegacyArea extends StatelessWidget {
  const LegacyArea({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(SkyRadii.sheet)),
    this.removeTopPadding = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool removeTopPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    final theme = SkyThemes.legacy(tokens);
    Widget body = Theme(
      data: theme,
      child: DefaultTextStyle(
        style: AppTheme.bodyText,
        child: IconTheme(data: theme.iconTheme, child: child),
      ),
    );
    if (removeTopPadding) {
      body = MediaQuery.removePadding(context: context, removeTop: true, child: body);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.body),
        child: Material(type: MaterialType.transparency, child: body),
      ),
    );
  }
}
