/// Core size ceilings shared by local persistence and WebRTC wire sync.
/// Derived dynamically so local storage cannot accept an image that exceeds wire capacity.
library;

const double base64Inflation = 4.0 / 3.0;

/// Ceiling on a SINGLE record, measured on the serialized wire record (i.e. AFTER blob base64 encoding).
const int maxSingleRecordBytes = 16 * 1024 * 1024; // 16 MB

/// Headroom left for envelope metadata, JSON punctuation, id, timestamps.
const double nonBlobHeadroom = 0.75;

/// Ceiling on a photo's encrypted bytes as stored locally (~9 MB).
final int maxImageBlobBytes =
    ((maxSingleRecordBytes / base64Inflation) * nonBlobHeadroom).floor();

/// Outbound batch budget for SYNC_RECORDS_BATCH (512 KB).
const int maxBatchPayloadBytes = 512 * 1024;

void validateLimits() {
  if (maxImageBlobBytes * base64Inflation >= maxSingleRecordBytes) {
    throw StateError(
      'maxImageBlobBytes exceeds maxSingleRecordBytes once base64-encoded.',
    );
  }
}
