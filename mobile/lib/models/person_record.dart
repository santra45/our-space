class PronounSet {
  const PronounSet({
    required this.subject,
    required this.object,
    required this.possessive,
    required this.independent,
    required this.has,
    required this.isVerb,
  });

  final String subject;
  final String object;
  final String possessive;
  final String independent;
  final String has;
  final String isVerb;
}

class Person {
  const Person({
    required this.personId,
    required this.name,
    required this.pronoun,
    required this.deviceIds,
    required this.lastActiveAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String personId;
  final String name;
  final String pronoun;
  final List<String> deviceIds;
  final int? lastActiveAt;
  final int createdAt;
  final int updatedAt;

  Person copyWith({int? lastActiveAt, bool clearLastActive = false}) => Person(
        personId: personId,
        name: name,
        pronoun: pronoun,
        deviceIds: deviceIds,
        lastActiveAt: clearLastActive ? null : (lastActiveAt ?? this.lastActiveAt),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toJson() => {
        'personId': personId,
        'name': name,
        'pronoun': pronoun,
        'deviceIds': deviceIds,
        'lastActiveAt': lastActiveAt,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class Presence {
  const Presence({required this.personId, required this.lastActiveAt});

  final String personId;
  final int lastActiveAt;
}

enum IdentityStatus { loading, locked, empty, unclaimed, ready }

class Identity {
  const Identity({required this.status, required this.people, required this.me, required this.partner});

  static const Identity loading = Identity(status: IdentityStatus.loading, people: [], me: null, partner: null);

  static const Identity locked = Identity(status: IdentityStatus.locked, people: [], me: null, partner: null);

  final IdentityStatus status;
  final List<Person> people;
  final Person? me;
  final Person? partner;

  String? get myOwnerId => me?.personId;

  Set<String> get myOwnerIds => {
        if (me != null) me!.personId,
        ...?me?.deviceIds,
      };
}
