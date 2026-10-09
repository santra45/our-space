import 'package:flutter/painting.dart';

abstract final class AppRadii {
  static const double sm = 2;
  static const double base = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double x2l = 16;
  static const double x3l = 24;
  static const double x4l = 32;
  static const double x5l = 40;
  static const double full = 9999;

  static BorderRadius all(double radius) => BorderRadius.all(Radius.circular(radius));

  static BorderRadius top(double radius) => BorderRadius.vertical(top: Radius.circular(radius));
}

abstract final class TwSpace {
  static double of(num units) => units * 4.0;
}

abstract final class AppLayout {
  static const double maxWidthXs = 320;
  static const double maxWidthSm = 384;
  static const double maxWidthMd = 448;

  static const double pagePaddingX = 16;
  static const double pagePaddingTop = 16;
  static const double pageBottomExtra = 88;

  static const double headerMinTopPadding = 12;
  static const double headerBottomPadding = 12;
  static const double headerRowHeight = 32;

  static const double navTopPadding = 8;
  static const double navBottomPadding = 6;
  static const double navSidePadding = 12;

  static const double modalScreenPadding = 16;
  static const double modalMaxHeightFactor = 0.9;
  static const double sheetMaxHeightFactor = 0.92;
}
