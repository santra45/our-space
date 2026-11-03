import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../sky/together/sky_together_scope.dart';
import '../us/us_copy.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'watch_chat.dart';
import 'watch_copy.dart';

abstract final class FilmKeys {
  static const Key shelf = ValueKey<String>('films-shelf');
  static const Key title = ValueKey<String>('film-title');
  static const Key save = ValueKey<String>('film-save');
  static const Key remove = ValueKey<String>('film-remove');
  static const Key said = ValueKey<String>('film-said');

  static Key film(String id) => ValueKey<String>('film-$id');

  static Key line(String id) => ValueKey<String>('film-line-$id');
}

class FilmsShelf extends StatefulWidget {
  const FilmsShelf({super.key = FilmKeys.shelf, required this.partner});

  final String partner;

  @override
  State<FilmsShelf> createState() => _FilmsShelfState();
}

class _FilmsShelfState extends State<FilmsShelf> {
  StreamSubscription<TableSnapshot<FilmRecord>>? _subscription;
  List<FilmRecord> _films = const [];

  @override
  void initState() {
    super.initState();
    _subscription = context.space.films.watch().listen((snapshot) {
      if (mounted) setState(() => _films = snapshot.items);
    }, onError: (Object error) {});
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _open(FilmRecord film) async {
    final films = context.space.films;
    final filmLines = context.space.filmLines;
    final me = SkyTogetherScope.maybeOf(context)?.owner;
    final lines = filmLines.ofFilm(film.id).catchError((Object _) => const <FilmLineRecord>[]);
    final action = await showSkySheet<FilmAction>(
      context: context,
      builder: (_) => FilmSheet(
        film: film,
        lines: lines,
        me: me,
        partner: widget.partner,
        onSave: (title) async {
          try {
            return await films.rename(film, title) == null ? SaveOutcome.skipped : SaveOutcome.saved;
          } catch (_) {
            return SaveOutcome.failed;
          }
        },
      ),
    );
    if (action != FilmAction.removed) return;
    unawaited(films.remove(film.id).catchError((Object _) => null));
    unawaited(filmLines.removeFilm(film.id).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    if (_films.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: SkySpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkySectionHeader(title: WatchCopy.filmsTitle),
          for (final film in _films)
            Padding(
              padding: const EdgeInsets.only(top: SkySpace.sm),
              child: _FilmTicket(key: FilmKeys.film(film.id), film: film, onTap: () => unawaited(_open(film))),
            ),
        ],
      ),
    );
  }
}

class _FilmTicket extends StatelessWidget {
  const _FilmTicket({super.key, required this.film, required this.onTap});

  final FilmRecord film;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final line = WatchCopy.filmLine(UsDates.long(DateTime.fromMillisecondsSinceEpoch(film.watchedAt)), film.togetherMs);
    return SkyCard(
      onTap: onTap,
      semanticLabel: '${film.title}, $line',
      child: Row(
        children: [
          SkyIcon(SkyIcons.film, size: 22, color: t.rose),
          const SizedBox(width: SkySpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(film.title, style: context.skyText.serifItem, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(line, style: context.skyText.bodySmall.copyWith(color: t.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum FilmAction { saved, removed }

class FilmSheet extends StatefulWidget {
  const FilmSheet({super.key, required this.film, required this.onSave, this.lines, this.me, this.partner = ''});

  final FilmRecord film;
  final Future<SaveOutcome> Function(String title) onSave;
  final Future<List<FilmLineRecord>>? lines;
  final String? me;
  final String partner;

  @override
  State<FilmSheet> createState() => _FilmSheetState();
}

class _FilmSheetState extends State<FilmSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.film.title);
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await widget.onSave(_title.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == SaveOutcome.failed;
    });
    if (outcome == SaveOutcome.saved) Navigator.of(context).pop(FilmAction.saved);
  }

  Future<void> _remove() async {
    final confirmed = await showSkyConfirm(
      context,
      title: WatchCopy.filmRemoveTitle,
      message: WatchCopy.filmRemoveNote,
      confirmLabel: WatchCopy.filmRemoveYes,
      cancelLabel: WatchCopy.filmKeep,
      destructive: true,
      icon: SkyIcons.trash,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(FilmAction.removed);
  }

  Widget _said(FilmLineRecord line) {
    final mine = line.by == widget.me;
    return WatchChatBubble(
      key: FilmKeys.line(line.id),
      text: line.text,
      note: WatchCopy.clock(line.posMs),
      mine: mine,
      label: mine ? WatchCopy.youSaid(line.text) : WatchCopy.partnerSaid(widget.partner, line.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UsSheetFrame(
      kicker: WatchCopy.filmsTitle,
      title: WatchCopy.filmEditTitle,
      children: [
        SkyTextField(
          key: FilmKeys.title,
          controller: _title,
          label: WatchCopy.filmNameLabel,
          maxLength: filmTitleLimit,
          textInputAction: TextInputAction.done,
        ),
        if (_failed)
          const Padding(
            padding: EdgeInsets.only(top: SkySpace.lg),
            child: SkyNotice(text: WatchCopy.filmSaveFailed, tone: SkyNoticeTone.error),
          ),
        FutureBuilder<List<FilmLineRecord>>(
          future: widget.lines,
          builder: (context, snapshot) {
            final lines = snapshot.data ?? const <FilmLineRecord>[];
            if (lines.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: SkySpace.xl),
              child: Column(
                key: FilmKeys.said,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(WatchCopy.filmSaid, style: context.skyText.serifItem),
                  const SizedBox(height: SkySpace.sm),
                  for (final line in lines) _said(line),
                ],
              ),
            );
          },
        ),
        UsSheetActions(
          primary: ListenableBuilder(
            listenable: _title,
            builder: (context, _) => SkyButton(
              key: FilmKeys.save,
              label: WatchCopy.filmSave,
              icon: SkyIcons.check,
              busy: _busy,
              onPressed: _title.text.trim().isEmpty ? null : () => unawaited(_save()),
            ),
          ),
          secondary: SkyButton(
            key: FilmKeys.remove,
            label: WatchCopy.filmRemove,
            icon: SkyIcons.trash,
            variant: SkyButtonVariant.danger,
            onPressed: _busy ? null : () => unawaited(_remove()),
          ),
        ),
      ],
    );
  }
}
