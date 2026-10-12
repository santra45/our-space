import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/our_widgets.dart';

const Duration layoutGlideDuration = Duration(milliseconds: 450);
const Curve layoutGlideCurve = Cubic(0.4, 0, 0.1, 1);

class GlideScope extends SingleChildRenderObjectWidget {
  const GlideScope({super.key, super.child});

  @override
  RenderGlideScope createRenderObject(BuildContext context) => RenderGlideScope();
}

class RenderGlideScope extends RenderProxyBox {}

class LayoutGlide extends StatefulWidget {
  const LayoutGlide({super.key, required this.child});

  final Widget child;

  @override
  State<LayoutGlide> createState() => _LayoutGlideState();
}

class _LayoutGlideState extends State<LayoutGlide> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: layoutGlideDuration)
    ..value = 1;
  Offset _from = Offset.zero;
  Offset? _last;
  bool _restartPending = false;
  bool _motion = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = motionAllowed(context);
    if (!_motion) {
      _controller.stop();
      _controller.value = 1;
      _restartPending = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset get currentShift {
    if (_restartPending) return _from;
    if (_controller.value >= 1) return Offset.zero;
    return _from * (1 - layoutGlideCurve.transform(_controller.value));
  }

  Offset shiftAt(Offset? position) {
    if (position == null) return currentShift;
    final last = _last;
    _last = position;
    if (last == null || !_motion || (last - position).distance < 0.5) return currentShift;
    _from = last + currentShift - position;
    if (!_restartPending) {
      _restartPending = true;
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        if (!mounted || !_restartPending) return;
        _restartPending = false;
        _controller.forward(from: 0);
      });
    }
    return _from;
  }

  @override
  Widget build(BuildContext context) => _GlideBox(state: this, repaint: _controller, child: widget.child);
}

class _GlideBox extends SingleChildRenderObjectWidget {
  const _GlideBox({required this.state, required this.repaint, super.child});

  final _LayoutGlideState state;
  final Listenable repaint;

  @override
  _RenderGlide createRenderObject(BuildContext context) => _RenderGlide(state, repaint);

  @override
  void updateRenderObject(BuildContext context, _RenderGlide renderObject) {
    renderObject
      ..state = state
      ..repaint = repaint;
  }
}

class _RenderGlide extends RenderProxyBox {
  _RenderGlide(this.state, this._repaint);

  _LayoutGlideState state;
  Listenable _repaint;

  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  Offset? _positionInScope() {
    RenderObject? node = parent;
    while (node != null && node is! RenderGlideScope) {
      node = node.parent;
    }
    if (node == null) return null;
    return MatrixUtils.transformPoint(getTransformTo(node), Offset.zero);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final shift = state.shiftAt(_positionInScope());
    context.paintChild(child, offset + shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: state.currentShift,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = state.currentShift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
