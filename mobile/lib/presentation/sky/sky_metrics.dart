import 'package:flutter/widgets.dart';

abstract final class SkySpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double xxl = 26;
  static const double gutter = 18;
  static const double topBarSide = 22;
  static const double topBarGap = 14;
  static const double sectionGap = 26;
}

abstract final class SkyRadii {
  static const double xs = 6;
  static const double sm = 11;
  static const double md = 14;
  static const double button = 16;
  static const double tile = 18;
  static const double field = 16;
  static const double paper = 20;
  static const double card = 22;
  static const double feature = 26;
  static const double sheet = 32;
  static const double pill = 99;

  static BorderRadius all(double radius) => BorderRadius.circular(radius);

  static BorderRadius top(double radius) => BorderRadius.vertical(top: Radius.circular(radius));
}

abstract final class SkySizes {
  static const double iconButton = 42;
  static const double avatar = 42;
  static const double button = 48;
  static const double buttonCompact = 44;
  static const double rowIcon = 36;
  static const double toggleWidth = 46;
  static const double toggleHeight = 28;
  static const double toggleKnob = 22;
  static const double progress = 6;
  static const double grabWidth = 40;
  static const double grabHeight = 4;
  static const double dockHeight = 62;
  static const double dockSide = 16;
  static const double dockBottom = 18;
  static const double dockLoveOuter = 58;
  static const double dockLoveInner = 48;
  static const double dockLoveLift = 15;
  static const double dockSlotWidth = 56;
  static const double skyHeight = 360;
  static const double maxContentWidth = 520;

  static double dockClearance(double safeBottom) => safeBottom + dockBottom + dockHeight + 18;
}
