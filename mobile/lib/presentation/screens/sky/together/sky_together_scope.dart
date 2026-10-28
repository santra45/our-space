import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';

class SkyTogetherScope extends InheritedWidget {
  const SkyTogetherScope({super.key, required this.link, this.drawings, required super.child});

  final SkyTogetherLink link;
  final SkyDrawingService? drawings;

  static SkyTogetherScope? _scope(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkyTogetherScope>();

  static OurSpace? _space(BuildContext context) {
    try {
      return Provider.of<OurSpace>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  static SkyTogetherLink? maybeOf(BuildContext context) => _scope(context)?.link ?? _space(context)?.peer.skyTogether;

  static SkyDrawingService? drawingsOf(BuildContext context) =>
      _scope(context)?.drawings ?? _space(context)?.skyDrawings;

  @override
  bool updateShouldNotify(SkyTogetherScope oldWidget) =>
      !identical(oldWidget.link, link) || !identical(oldWidget.drawings, drawings);
}
