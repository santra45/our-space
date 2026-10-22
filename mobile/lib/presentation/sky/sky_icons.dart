import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'sky_tokens.dart';

enum SkyIcons {
  star,
  sparkle,
  letter,
  photo,
  us,
  heart,
  plus,
  camera,
  back,
  chevron,
  moon,
  lock,
  finger,
  bell,
  phone,
  box,
  download,
  upload,
  pen,
  check,
  calendar,
  dice,
  dots,
  key,
  close,
  alert,
  info,
  trash,
  share,
  scan,
  copy,
  link,
  refresh,
  eye,
  eyeOff,
  sun,
  clock,
  sealedStar,
}

const Map<SkyIcons, String> _paths = {
  SkyIcons.star: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z" fill="currentColor" fill-opacity="0.25" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/>',
  SkyIcons.sparkle: '<path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z" fill="currentColor" fill-opacity="0.3" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  SkyIcons.letter: '<rect x="2.5" y="4.5" width="19" height="15" rx="3" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M3 7l9 6.2L21 7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.photo: '<rect x="3" y="3" width="18" height="18" rx="3.5" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><circle cx="8.8" cy="8.8" r="1.7" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M21 15.5l-5-5L5 21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.us: '<circle cx="8.5" cy="8" r="3.5" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><circle cx="16.5" cy="9" r="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M2.5 20c.8-3.4 3.2-5.2 6-5.2s5.2 1.8 6 5.2M15 14.9c2.6-.4 5 1.1 6 4.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.heart: '<path d="M12 20.5l-1.3-1.2C5.6 14.6 2.5 11.8 2.5 8.4A4.9 4.9 0 0 1 7.4 3.5c1.7 0 3.4.8 4.6 2.1 1.2-1.3 2.9-2.1 4.6-2.1a4.9 4.9 0 0 1 4.9 4.9c0 3.4-3.1 6.2-8.2 10.9z" fill="currentColor" fill-opacity="0.35" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/>',
  SkyIcons.plus:
      '<path d="M12 5v14M5 12h14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  SkyIcons.camera: '<path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h1.2l1.4-2h5.8l1.4 2h1.2A2.5 2.5 0 0 1 20 8.5v9a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5z" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="12" cy="13" r="3.4" fill="none" stroke="currentColor" stroke-width="1.8"/>',
  SkyIcons.back: '<path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.chevron: '<path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.moon: '<path d="M20.5 13.2A8.6 8.6 0 1 1 10.8 3.5 6.7 6.7 0 0 0 20.5 13.2z" fill="currentColor" fill-opacity="0.3" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  SkyIcons.lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.6" fill="currentColor" fill-opacity="0.2" stroke="currentColor" stroke-width="1.8"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.finger: '<path d="M7.5 10.5a4.5 4.5 0 0 1 9 0c0 3.6-.6 6.6-1.8 9M12 10.5c0 4-.8 7.4-2.6 10M4.8 14.5c.3-1.3.5-2.6.5-4a6.7 6.7 0 0 1 11.6-4.6M19.2 9.4c.3 1.3.4 2.8.3 4.6M9.6 10.5c0 2.6-.3 5-1.2 7" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  SkyIcons.bell: '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.phone: '<rect x="6.5" y="2.5" width="11" height="19" rx="3" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M10.5 18.5h3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.box: '<path d="M4 8l8-4.5L20 8v8.5L12 21l-8-4.5z" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M4 8l8 4.5L20 8M12 12.5V21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  SkyIcons.download: '<path d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.upload: '<path d="M12 15V4M7.5 8.5L12 4l4.5 4.5M5 19.5h14" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.pen: '<path d="M4 20l1-4.2L15.6 5.2a2 2 0 0 1 2.8 0l.4.4a2 2 0 0 1 0 2.8L8.2 19z" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  SkyIcons.check: '<path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="3" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M3.5 9.5h17M8 3v4M16 3v4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.dice: '<rect x="3.5" y="3.5" width="17" height="17" rx="4" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><circle cx="8.5" cy="8.5" r="1.3" fill="currentColor"/><circle cx="15.5" cy="15.5" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/>',
  SkyIcons.dots: '<circle cx="5.5" cy="12" r="1.7" fill="currentColor"/><circle cx="12" cy="12" r="1.7" fill="currentColor"/><circle cx="18.5" cy="12" r="1.7" fill="currentColor"/>',
  SkyIcons.key: '<circle cx="8" cy="12" r="4" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8"/><path d="M12 12h8.5M17.5 12v3M20.5 12v2.2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  SkyIcons.alert: '<path d="M10.3 4.4a2 2 0 0 1 3.4 0l7.6 13.1a2 2 0 0 1-1.7 3H4.4a2 2 0 0 1-1.7-3z" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 9.5v4.2" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><circle cx="12" cy="16.9" r="1.1" fill="currentColor"/>',
  SkyIcons.info: '<circle cx="12" cy="12" r="9" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M12 11v5.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><circle cx="12" cy="7.8" r="1.1" fill="currentColor"/>',
  SkyIcons.trash: '<path d="M5.5 7h13l-1 12.2a2 2 0 0 1-2 1.8h-7a2 2 0 0 1-2-1.8z" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M3.5 7h17M9.5 7V4.5h5V7M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.share: '<path d="M8.4 10.8l7.2-4.1M8.4 13.2l7.2 4.1" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="18" cy="5.5" r="2.6" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8"/><circle cx="6" cy="12" r="2.6" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8"/><circle cx="18" cy="18.5" r="2.6" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8"/>',
  SkyIcons.scan: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><rect x="8" y="8" width="8" height="8" rx="1.6" fill="currentColor" fill-opacity="0.15" stroke="currentColor" stroke-width="1.8"/>',
  SkyIcons.copy: '<rect x="8" y="8" width="12" height="12" rx="2.6" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M16 8V6.6A2.6 2.6 0 0 0 13.4 4H6.6A2.6 2.6 0 0 0 4 6.6v6.8A2.6 2.6 0 0 0 6.6 16H8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.refresh: '<path d="M20 12a8 8 0 1 1-2.6-5.9M20 4.5v4.5h-4.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" stroke-width="1.8"/>',
  SkyIcons.eyeOff: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M4 4l16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>',
  SkyIcons.sun: '<circle cx="12" cy="12" r="4.2" fill="currentColor" fill-opacity="0.3" stroke="currentColor" stroke-width="1.8"/><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  SkyIcons.clock: '<circle cx="12" cy="12" r="9" fill="currentColor" fill-opacity="0.12" stroke="currentColor" stroke-width="1.8"/><path d="M12 7.5V12l3 2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
  SkyIcons.sealedStar: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z" fill="#FFD98A" fill-opacity="0.35" stroke="#E8B04B" stroke-width="1.5" stroke-linejoin="round"/><rect x="9" y="11" width="6" height="4.6" rx="1" fill="#8A5A12"/><path d="M10.2 11V9.8a1.8 1.8 0 0 1 3.6 0V11" stroke="#8A5A12" stroke-width="1.2" fill="none"/>',
};

const Set<SkyIcons> skyDesignIcons = {
  SkyIcons.star,
  SkyIcons.sparkle,
  SkyIcons.letter,
  SkyIcons.photo,
  SkyIcons.us,
  SkyIcons.heart,
  SkyIcons.plus,
  SkyIcons.camera,
  SkyIcons.back,
  SkyIcons.chevron,
  SkyIcons.moon,
  SkyIcons.lock,
  SkyIcons.finger,
  SkyIcons.bell,
  SkyIcons.phone,
  SkyIcons.box,
  SkyIcons.download,
  SkyIcons.upload,
  SkyIcons.pen,
  SkyIcons.check,
  SkyIcons.calendar,
  SkyIcons.dice,
  SkyIcons.dots,
  SkyIcons.key,
};

extension SkyIconSvg on SkyIcons {
  String get body => _paths[this]!;

  String get svg => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">${_paths[this]!}</svg>';

  bool get multicolor => this == SkyIcons.sealedStar;
}

class SkyIcon extends StatelessWidget {
  const SkyIcon(this.icon, {super.key, this.size = 20, this.color, this.semanticLabel});

  final SkyIcons icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  Color resolveColor(BuildContext context) =>
      color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? context.sky.text;

  @override
  Widget build(BuildContext context) {
    final tint = resolveColor(context);
    final picture = SvgPicture.string(
      icon.svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: tint),
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
    return SizedBox(width: size, height: size, child: picture);
  }
}
