library;

const int pbkdf2IterationsCurrent = 600000;
const int pbkdf2IterationsLegacy = 250000;
const int aesKeyLengthBits = 256;
const int ivLengthBytes = 12;
const int saltLengthBytes = 16;
const int minPassphraseLength = 16;

const String vaultCanaryToken = 'SWEETHEART_CANARY_VALIDATION_TOKEN';
const int recordSchemaVersion = 2;

const String protocolId = 'SWEETHEART_V2';
const String legacyProtocolId = 'SWEETHEART_V1';

const int maxClockSkewMs = 24 * 60 * 60 * 1000;
const int syncSessionTimeoutMs = 120000;
const int heartbeatIntervalMs = 15000;
const int heartbeatTimeoutMs = 50000;

const List<String> syncedTables = [
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
  'loveBursts',
  'dailyAnswers',
  'people',
];
