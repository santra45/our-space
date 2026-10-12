enum PeerLinkState { disconnected, connecting, connected, authorised, syncing }

class PeerStatus {
  PeerStatus(Map<String, Object?> fields) : fields = Map<String, Object?>.unmodifiable(fields);

  static final PeerStatus initial = PeerStatus(const {'state': 'disconnected'});

  final Map<String, Object?> fields;

  String get state => _string('state') ?? 'disconnected';
  String? get code => _string('code');
  String? get error => _string('error');
  String? get warning => _string('warning');
  String? get message => _string('message');
  String? get partnerId => _string('partnerId');
  String? get peerId => _string('peerId');
  String? get errorType => _string('errorType');
  String? get connectionType => _string('connectionType');
  bool get hasConnectionType => fields.containsKey('connectionType');
  bool get isDirect => fields['isDirect'] == true;

  int get applied => _int('applied');
  int get rejected => _int('rejected');
  int get unverifiable => _int('unverifiable');
  int get sent => _int('sent');

  String? _string(String key) {
    final value = fields[key];
    return value is String ? value : null;
  }

  int _int(String key) {
    final value = fields[key];
    return value is num ? value.toInt() : 0;
  }

  @override
  String toString() => 'PeerStatus($fields)';
}

class PeerDataUpdate {
  const PeerDataUpdate({required this.count, this.single = false, this.table});

  final int count;
  final bool single;
  final String? table;
}

class PeerConfigUpdate {
  const PeerConfigUpdate({required this.coupleNames, required this.startDate, required this.updatedAt});

  final String coupleNames;
  final String startDate;
  final num updatedAt;
}

class PeerSyncError {
  const PeerSyncError({required this.code, required this.state, required this.text});

  final String code;
  final String state;
  final String text;
}

class PendingPeerInvite {
  const PendingPeerInvite({required this.peerId, required this.fromLink});

  final String peerId;
  final bool fromLink;
}

const Set<String> authorizedPeerStates = {'authorized', 'syncing', 'synced'};

const Set<String> routeClearingPeerStates = {'disconnected', 'error', 'auth_failed', 'ice_failed'};
