import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'vault_gate.dart';

const String inviteLinkScheme = 'https';

final String inviteLinkHost = Uri.parse(defaultInviteBaseUrl).host;

Invite? inviteFromLink(String? link) {
  if (link == null) return null;
  final text = link.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != inviteLinkScheme || uri.host != inviteLinkHost) return null;
  return parseInvite(text);
}

Stream<String> platformLinks() {
  if (kIsWeb || !Platform.isAndroid) return const Stream<String>.empty();
  return AppLinks().stringLinkStream;
}

class InviteInbox extends ChangeNotifier {
  InviteInbox([Stream<String>? links]) {
    if (links != null) _subscription = links.listen(deliver, onError: (Object _) {});
  }

  static InviteInbox? _platform;

  static InviteInbox get platform => _platform ??= InviteInbox(platformLinks());

  StreamSubscription<String>? _subscription;
  Invite? _pending;
  int _arrivals = 0;

  Invite? get pending => _pending;

  int get arrivals => _arrivals;

  bool deliver(String link) {
    final invite = inviteFromLink(link);
    if (invite == null) return false;
    _pending = invite;
    _arrivals++;
    notifyListeners();
    return true;
  }

  void consume() => _pending = null;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class InviteLinkGate extends StatefulWidget {
  const InviteLinkGate({super.key, required this.shell, this.inbox});

  final Widget shell;
  final InviteInbox? inbox;

  @override
  State<InviteLinkGate> createState() => _InviteLinkGateState();
}

class _InviteLinkGateState extends State<InviteLinkGate> {
  late InviteInbox _inbox;
  late int _seen;
  Invite? _invite;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _attach(widget.inbox ?? InviteInbox.platform);
  }

  @override
  void didUpdateWidget(covariant InviteLinkGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.inbox ?? InviteInbox.platform;
    if (identical(next, _inbox)) return;
    _inbox.removeListener(_onArrival);
    _attach(next);
  }

  void _attach(InviteInbox inbox) {
    _inbox = inbox;
    _seen = inbox.arrivals;
    _invite = inbox.pending;
    inbox.addListener(_onArrival);
  }

  void _onArrival() {
    if (!mounted || _inbox.arrivals == _seen) return;
    _seen = _inbox.arrivals;
    final invite = _inbox.pending;
    if (invite == null) return;
    final vault = context.read<VaultService>();
    if (vault.isUnlocked) {
      vault.lock();
      setState(() => _invite = invite);
      return;
    }
    setState(() {
      _invite = invite;
      _generation++;
    });
  }

  @override
  void dispose() {
    _inbox.removeListener(_onArrival);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.watch<VaultService>().isUnlocked;
    if (unlocked && _invite != null) {
      _invite = null;
      _inbox.consume();
    }
    return VaultGate(key: ValueKey(_generation), shell: widget.shell, invite: _invite);
  }
}
