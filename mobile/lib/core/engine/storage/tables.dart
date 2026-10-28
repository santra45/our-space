const String memoriesTable = 'memories';
const String milestonesTable = 'milestones';
const String dateIdeasTable = 'dateIdeas';
const String lettersTable = 'letters';
const String bucketListTable = 'bucketList';
const String loveBurstsTable = 'loveBursts';
const String dailyAnswersTable = 'dailyAnswers';
const String peopleTable = 'people';
const String skyDrawingsTable = 'skyDrawings';
const String vaultMetaTable = 'vaultMeta';

const List<String> syncedTables = [
  memoriesTable,
  milestonesTable,
  dateIdeasTable,
  lettersTable,
  bucketListTable,
  loveBurstsTable,
  dailyAnswersTable,
  peopleTable,
  skyDrawingsTable,
];

const Set<String> importableTables = {
  memoriesTable,
  milestonesTable,
  dateIdeasTable,
  lettersTable,
  bucketListTable,
  loveBurstsTable,
  dailyAnswersTable,
  peopleTable,
  skyDrawingsTable,
};

const List<String> exportedTables = [vaultMetaTable, ...syncedTables];

const Set<String> appOnlyTables = {skyDrawingsTable};

const int maxBackupFileBytes = 150 * 1024 * 1024;

const int maxRecordsPerTable = 20000;

const int maxClockSkewMs = 24 * 60 * 60 * 1000;

const Map<String, List<String>> binaryFieldsByTable = {
  memoriesTable: ['imageBlob'],
};
