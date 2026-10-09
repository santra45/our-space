const double base64Inflation = 4 / 3;

const int maxSingleRecordBytes = 16 * 1024 * 1024;

const double _nonBlobHeadroom = 0.75;

final int maxImageBlobBytes = ((maxSingleRecordBytes / base64Inflation) * _nonBlobHeadroom).floor();

const int maxBatchPayloadBytes = 512 * 1024;

const int maxMailboxObjectBytes = 16 * 1024 * 1024;
