import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../memories_copy.dart';
import '../memory_photos.dart';

class MemoryMonth {
  const MemoryMonth(this.month, this.items);

  final DateTime? month;
  final List<MemoryRecord> items;
}

List<MemoryMonth> groupMemoriesByMonth(List<MemoryRecord> items) {
  final months = <MemoryMonth>[];
  DateTime? current;
  var bucket = <MemoryRecord>[];
  var started = false;
  for (final memory in items) {
    final day = memoryDay(memory);
    final month = day == null ? null : DateTime(day.year, day.month);
    if (!started || month != current) {
      if (started) months.add(MemoryMonth(current, bucket));
      current = month;
      bucket = <MemoryRecord>[];
      started = true;
    }
    bucket.add(memory);
  }
  if (started) months.add(MemoryMonth(current, bucket));
  return months;
}

abstract final class MemoryWallMetrics {
  static const double side = 16;
  static const double top = 14;
  static const double gap = 14;
  static const double below = 18;
  static const double paperPad = 9;

  static double columnWidth(double contentWidth) => math.max(0, (contentWidth - side * 2 - gap) / 2);
}

double estimatePolaroidHeight(MemoryRecord memory, double columnWidth) {
  final inner = math.max(1.0, columnWidth - MemoryWallMetrics.paperPad * 2);
  final photo = inner * PolaroidLook.ratioOf(memory.id);
  final perLine = math.max(6.0, (inner - 4) / 7.5);
  final lines = (calmCaption(memory.caption).length / perLine).ceil().clamp(1, 2);
  return MemoryWallMetrics.paperPad + photo + 8 + lines * 20 + 24 + MemoryWallMetrics.below;
}

class WallColumns {
  const WallColumns(this.left, this.right);

  final List<MemoryRecord> left;
  final List<MemoryRecord> right;
}

WallColumns splitIntoColumns(List<MemoryRecord> items, double columnWidth) {
  final left = <MemoryRecord>[];
  final right = <MemoryRecord>[];
  var leftHeight = 0.0;
  var rightHeight = 0.0;
  for (final memory in items) {
    final height = estimatePolaroidHeight(memory, columnWidth);
    if (leftHeight <= rightHeight) {
      left.add(memory);
      leftHeight += height;
    } else {
      right.add(memory);
      rightHeight += height;
    }
  }
  return WallColumns(left, right);
}

class MonthDivider extends StatelessWidget {
  const MonthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.xl, SkySpace.gutter, SkySpace.xs),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Text(label.toUpperCase(), style: SkyType.label.copyWith(color: context.sky.gold)),
            const SizedBox(width: 10),
            const Expanded(child: SkyDivider()),
          ],
        ),
      ),
    );
  }
}

typedef WallTileBuilder = Widget Function(BuildContext context, MemoryRecord memory);

String monthLabelOf(DateTime? month, {DateTime? now}) =>
    month == null ? MemoriesCopy.undated : MemoriesCopy.month(month, now: now);

Widget _monthColumns(
  List<MemoryRecord> items,
  double columnWidth,
  Widget Function(List<MemoryRecord> items, EdgeInsets padding) column,
) {
  final columns = splitIntoColumns(items, columnWidth);
  return SliverCrossAxisGroup(
    slivers: [
      column(columns.left, const EdgeInsets.only(right: MemoryWallMetrics.gap / 2)),
      column(columns.right, const EdgeInsets.only(left: MemoryWallMetrics.gap / 2)),
    ],
  );
}

List<Widget> memoryWallSlivers({
  required List<MemoryMonth> months,
  required double contentWidth,
  required WallTileBuilder tileBuilder,
  DateTime? now,
}) {
  final columnWidth = MemoryWallMetrics.columnWidth(contentWidth);
  Widget column(List<MemoryRecord> items, EdgeInsets padding) {
    return SliverCrossAxisExpanded(
      flex: 1,
      sliver: SliverPadding(
        padding: padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final memory = items[index];
              return Padding(
                key: ValueKey<String>('wall-${memory.id}'),
                padding: const EdgeInsets.only(bottom: MemoryWallMetrics.below),
                child: tileBuilder(context, memory),
              );
            },
            childCount: items.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = items.indexWhere((memory) => 'wall-${memory.id}' == key.value);
              return index < 0 ? null : index;
            },
          ),
        ),
      ),
    );
  }

  return [
    for (final month in months) ...[
      SliverToBoxAdapter(
        key: ValueKey<String>('month-${month.month?.toIso8601String() ?? 'undated'}'),
        child: MonthDivider(label: monthLabelOf(month.month, now: now)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          MemoryWallMetrics.side,
          MemoryWallMetrics.top,
          MemoryWallMetrics.side,
          0,
        ),
        sliver: _monthColumns(month.items, columnWidth, column),
      ),
    ],
  ];
}
