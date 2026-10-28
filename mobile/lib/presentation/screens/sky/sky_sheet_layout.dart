import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../sky/sky.dart';

class SkySheetLayout extends SingleChildRenderObjectWidget {
  const SkySheetLayout({
    super.key,
    required this.viewport,
    required this.minTop,
    required this.maxTop,
    required super.child,
  });

  final double viewport;
  final double minTop;
  final double maxTop;

  @override
  RenderSkySheetLayout createRenderObject(BuildContext context) => RenderSkySheetLayout(viewport, minTop, maxTop);

  @override
  void updateRenderObject(BuildContext context, RenderSkySheetLayout renderObject) {
    renderObject
      ..viewport = viewport
      ..minTop = minTop
      ..maxTop = maxTop;
  }
}

class RenderSkySheetLayout extends RenderShiftedBox {
  RenderSkySheetLayout(this._viewport, this._minTop, this._maxTop, [RenderBox? child]) : super(child);

  double _viewport;
  double _minTop;
  double _maxTop;

  double get viewport => _viewport;
  set viewport(double value) {
    if (value == _viewport) return;
    _viewport = value;
    markNeedsLayout();
  }

  double get minTop => _minTop;
  set minTop(double value) {
    if (value == _minTop) return;
    _minTop = value;
    markNeedsLayout();
  }

  double get maxTop => _maxTop;
  set maxTop(double value) {
    if (value == _maxTop) return;
    _maxTop = value;
    markNeedsLayout();
  }

  double get _floor => math.min(_minTop, _maxTop);

  double get _ceiling => math.max(_minTop, _maxTop);

  double get _viewportHeight => _viewport.isFinite ? _viewport : _ceiling;

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: math.max(0.0, _viewportHeight - _ceiling),
    );
  }

  double topFor(double sheetHeight) => (_viewportHeight - sheetHeight).clamp(_floor, _ceiling);

  Size _sizeFor(BoxConstraints constraints, double top, double sheetHeight) =>
      constraints.constrain(Size(constraints.maxWidth, math.max(_viewportHeight, top + sheetHeight)));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(Size(constraints.maxWidth, _viewportHeight));
    final sheet = child.getDryLayout(_childConstraints(constraints));
    return _sizeFor(constraints, topFor(sheet.height), sheet.height);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(constraints.maxWidth, _viewportHeight));
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    final top = topFor(child.size.height);
    (child.parentData! as BoxParentData).offset = Offset(0, top);
    size = _sizeFor(constraints, top, child.size.height);
  }
}

class SkyPanel extends StatelessWidget {
  const SkyPanel({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: SkyRadii.top(SkyRadii.sheet),
        border: Border(top: BorderSide(color: t.cardBorder)),
        boxShadow: t.sheetShadow,
      ),
      child: ClipRRect(
        borderRadius: SkyRadii.top(SkyRadii.sheet),
        child: Stack(
          children: [
            if (t.isNight)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [t.gold.withValues(alpha: 0.1), t.gold.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const SkyGrabHandle(), child],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkyPageFrame extends StatelessWidget {
  const SkyPageFrame({
    super.key,
    required this.skyHeight,
    required this.sky,
    required this.sheet,
    this.top,
    this.minSheetTop,
    required this.maxSheetTop,
    this.controller,
    this.skyOverlay,
  });

  static const double designWidth = 390;

  final double skyHeight;
  final Widget sky;
  final Widget sheet;
  final Widget? top;
  final double? minSheetTop;
  final double maxSheetTop;
  final ScrollController? controller;
  final Widget? skyOverlay;

  static double scaleOf(double width) => math.min(width, SkySizes.maxContentWidth) / designWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, SkySizes.maxContentWidth);
        final k = width / designWidth;
        final wide = constraints.maxWidth > width;
        final content = SizedBox(
          width: width,
          child: Stack(
            children: [
              Positioned(top: 0, left: 0, right: 0, height: skyHeight * k, child: sky),
              SkySheetLayout(
                viewport: constraints.maxHeight,
                minTop: (minSheetTop ?? maxSheetTop) * k,
                maxTop: maxSheetTop * k,
                child: sheet,
              ),
              if (top != null) Positioned(top: 0, left: 0, right: 0, child: top!),
              if (skyOverlay != null) Positioned(top: 0, left: 0, right: 0, height: skyHeight * k, child: skyOverlay!),
            ],
          ),
        );
        return SingleChildScrollView(
          controller: controller,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Stack(
            children: [
              if (wide)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: skyHeight * k,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: t.skyGradient)),
                ),
              Center(child: content),
            ],
          ),
        );
      },
    );
  }
}
