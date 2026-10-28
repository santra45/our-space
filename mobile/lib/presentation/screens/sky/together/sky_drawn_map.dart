import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../sky_days.dart';
import '../sky_map_detail.dart';
import '../sky_map_plan.dart';
import 'sky_drawn.dart';

abstract final class SkyDrawnKeys {
  static const Key row = ValueKey<String>('sky-drawn-row');
  static const Key count = ValueKey<String>('sky-drawn-count');
  static const Key empty = ValueKey<String>('sky-drawn-empty');
  static const Key detail = ValueKey<String>('sky-drawn-detail');
  static const Key canvas = ValueKey<String>('sky-drawn-canvas');
  static const Key drawing = ValueKey<String>('sky-drawn-drawing');
  static const Key status = ValueKey<String>('sky-drawn-status');

  static Key tile(String id) => ValueKey<String>('sky-drawn-tile-$id');
}

abstract final class SkyDrawnCopy {
  static const String label = 'Ones we drew';
  static const String kicker = 'One we drew';
  static const String emptyTitle = 'Nothing drawn yet';
  static const String together = 'Drawn together';

  static String body({required bool night}) => night ? 'moon' : 'sun';

  static String emptyMessage({required bool night}) =>
      "When you're both here, hold the ${body(night: night)} together and draw one of your own";

  static String another({required bool night}) => 'Hold the ${body(night: night)} together to draw another';

  static String drawnBy(String? me, String? partner) =>
      me != null && partner != null ? 'Drawn by $me and $partner' : together;

  static String count(int count) => '$count';

  static String? lead({required bool night, int? number}) =>
      number == null ? null : '${night ? 'Night' : 'Day'} $number';

  static String _join(String? lead, String text) => lead == null ? text : '$lead · $text';

  static String meta(DateTime date, {required bool night, int? number}) =>
      _join(lead(night: night, number: number), DateFormat('d MMM', 'en_US').format(date));

  static String note(DateTime date, {required bool night, int? number}) =>
      _join(lead(night: night, number: number), DateFormat('EEEE, d MMMM', 'en_US').format(date));

  static String semantics(String name, DateTime date, {required bool night, int? number}) => [
    name,
    'drawn together',
    ?lead(night: night, number: number),
    DateFormat('d MMMM', 'en_US').format(date),
  ].join(', ');
}

@immutable
class SkyDrawnWhen {
  const SkyDrawnWhen({required this.date, this.number});

  factory SkyDrawnWhen.of(SkyDrawingRecord record, {DateTime? start}) {
    final keyed = dateFromDayKey(record.night);
    final made = record.createdAt ?? record.updatedAt;
    final date = keyed ?? SkyDays.dateOnly(DateTime.fromMillisecondsSinceEpoch(made));
    return SkyDrawnWhen(date: date, number: start == null ? null : SkyDays.dayNumber(start, date));
  }

  final DateTime date;
  final int? number;

  String meta({required bool night}) => SkyDrawnCopy.meta(date, night: night, number: number);

  String note({required bool night}) => SkyDrawnCopy.note(date, night: night, number: number);

  String semantics(String name, {required bool night}) =>
      SkyDrawnCopy.semantics(name, date, night: night, number: number);
}

class SkyDrawnWindow extends StatelessWidget {
  const SkyDrawnWindow({
    super.key,
    required this.sketch,
    this.size = defaultSize,
    this.drawing = defaultDrawing,
    this.stars = 16,
    this.seed = 31,
    this.radius = 14,
  });

  static const Size defaultSize = Size(124, 104);
  static const Rect defaultDrawing = Rect.fromLTWH(22, 14, 80, 76);

  static int seedFor(int index) => 31 + 13 * index;

  final SkyDrawnSketch sketch;
  final Size size;
  final Rect drawing;
  final int stars;
  final int seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    const night = SkyTokens.night;
    final scene = SkyScene(
      seed: seed,
      stars: stars,
      dayStars: 0,
      sun: false,
      clouds: const [],
      twinkle: false,
      designWidth: size.width,
    );
    return Theme(
      data: SkyThemes.legacy(night),
      child: Container(
        width: size.width,
        height: size.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: night.skyTop, borderRadius: SkyRadii.all(radius)),
        foregroundDecoration: BoxDecoration(
          borderRadius: SkyRadii.all(radius),
          border: Border.all(color: night.gold.withValues(alpha: 0.3)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: SkyBackdropPainter(scene: scene, tokens: night), isComplex: true),
            ),
            if (!sketch.isEmpty)
              Positioned.fromRect(
                rect: drawing,
                child: SkyDrawnView(sketch: sketch, style: SkyDrawnStyle.night, scale: 1),
              ),
          ],
        ),
      ),
    );
  }
}

class SkyDrawnTile extends StatelessWidget {
  const SkyDrawnTile({super.key, required this.record, required this.index, this.start, this.onTap});

  static const double width = 140;

  final SkyDrawingRecord record;
  final int index;
  final DateTime? start;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final when = SkyDrawnWhen.of(record, start: start);
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: when.semantics(record.name, night: t.isNight),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: SkyCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyDrawnWindow(sketch: SkyDrawnSketch.of(record.drawing), seed: SkyDrawnWindow.seedFor(index)),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SkyType.serif(16.5, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  when.meta(night: t.isNight),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SkyType.small.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SkyDrawnEmpty extends StatelessWidget {
  const SkyDrawnEmpty({super.key, required this.night});

  final bool night;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SkyDrawnWindow(sketch: SkyDrawnSketch.empty, size: const Size(60, 50), stars: 8, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  SkyDrawnCopy.emptyTitle,
                  style: SkyType.serif(18, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
                ),
                const SizedBox(height: 4),
                Text(SkyDrawnCopy.emptyMessage(night: night), style: SkyType.caption.copyWith(color: t.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkyDrawnMapRow extends StatelessWidget {
  const SkyDrawnMapRow({super.key, required this.drawings, this.start, this.onOpen});

  final List<SkyDrawingRecord> drawings;
  final DateTime? start;
  final ValueChanged<SkyDrawingRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final open = onOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, SkySpace.sm, 4, 0),
          child: Row(
            children: [
              const Expanded(child: SkyLabel(SkyDrawnCopy.label, icon: SkyIcons.pen, tone: SkyTone.rose)),
              if (drawings.isNotEmpty)
                Text(
                  SkyDrawnCopy.count(drawings.length),
                  key: SkyDrawnKeys.count,
                  style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: SkySpace.md),
        if (drawings.isEmpty)
          SkyDrawnEmpty(key: SkyDrawnKeys.empty, night: t.isNight)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < drawings.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  SkyDrawnTile(
                    key: SkyDrawnKeys.tile(drawings[i].id),
                    record: drawings[i],
                    index: i,
                    start: start,
                    onTap: open == null ? null : () => open(drawings[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> openSkyDrawn(BuildContext context, SkyDrawingRecord record) => skyPush<void>(
  context,
  (_) => SkyDrawnPage(record: record),
  settings: const RouteSettings(name: SkyDrawnPage.routeName),
);

class SkyDrawnPage extends StatefulWidget {
  const SkyDrawnPage({super.key, required this.record});

  static const String routeName = '/sky/map/drawn';
  static const double patchSide = 280;

  final SkyDrawingRecord record;

  static double fitScale(Rect room) => (math.min(room.width, room.height) / patchSide).clamp(0.9, 1.4);

  @override
  State<SkyDrawnPage> createState() => _SkyDrawnPageState();
}

class _SkyDrawnPageState extends State<SkyDrawnPage> {
  bool _leaving = false;

  void _leaveSoon() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    if (!vault.isUnlocked) {
      _leaveSoon();
      return const SkyScaffold(showSky: false, body: SizedBox.shrink());
    }
    final me = identity.me != null ? identity.myName : null;
    final partner = identity.partner != null ? identity.partnerName : null;
    final start = SkyDays.startOf(vault.config?.startDate);
    return _build(context, me: me, partner: partner, start: start);
  }

  Widget _build(BuildContext context, {required String? me, required String? partner, required DateTime? start}) {
    final t = context.sky;
    final night = t.isNight;
    final media = MediaQuery.of(context);
    final motion = skyMotionAllowed(context);
    final record = widget.record;
    final when = SkyDrawnWhen.of(record, start: start);
    final sketch = SkyDrawnSketch.of(record.drawing);

    final sky = LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final k = SkyMapPlan.scaleOf(size.width);
        final designWidth = size.width / k;
        final designHeight = size.height / k;
        final frame = SkyMapPlan.frameFor(
          size,
          media.viewPadding,
          top: SkyMapConstellationPage.topRoom,
          bottom: SkyMapConstellationPage.bottomRoom,
        );
        final room = frame.deflate(SkyMapPlan.margin / 2);
        final scene = SkyMapConstellationPage.sceneFor(
          const SkyConstellation(),
          designWidth: designWidth,
          designHeight: designHeight,
        ).copyWith(clearConstellation: true);
        return Semantics(
          container: true,
          image: true,
          label: when.semantics(record.name, night: night),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: motion ? 0 : 1, end: 1),
            duration: motion ? SkyMotion.slow : Duration.zero,
            curve: SkyMotion.gentle,
            builder: (context, dim, _) => Stack(
              fit: StackFit.expand,
              children: [
                SkyBackdrop(key: SkyDrawnKeys.canvas, scene: scene),
                Positioned(
                  left: room.left * k,
                  top: room.top * k,
                  width: room.width * k,
                  height: room.height * k,
                  child: SkyDrawnView(
                    key: SkyDrawnKeys.drawing,
                    sketch: sketch,
                    style: SkyDrawnStyle.of(t),
                    opacity: dim,
                    scale: k * SkyDrawnPage.fitScale(room),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final status = Container(
      key: SkyDrawnKeys.status,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.chip,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: t.chipBorder),
        boxShadow: t.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyIcon(SkyIcons.sparkle, size: 13, color: night ? t.gold : t.goldDeep),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              SkyDrawnCopy.drawnBy(me, partner),
              style: SkyType.sans(12, weight: FontWeight.w700, height: 1.2).copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );

    return SkyScaffold(
      key: SkyDrawnKeys.detail,
      showSky: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: sky),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SkyEntrance(
              child: SkyTopBar(
                compact: true,
                leading: const SkyBackButton(),
                kicker: SkyDrawnCopy.kicker,
                note: when.note(night: night),
                title: record.name,
              ),
            ),
          ),
          Positioned(
            left: SkySpace.gutter,
            right: SkySpace.gutter,
            bottom: media.viewPadding.bottom + SkySpace.xl,
            child: IgnorePointer(
              child: SkyEntrance(
                index: 2,
                offset: const Offset(0, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    status,
                    const SizedBox(height: SkySpace.sm),
                    Text(
                      SkyDrawnCopy.another(night: night),
                      textAlign: TextAlign.center,
                      style: SkyType.caption.copyWith(color: t.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
