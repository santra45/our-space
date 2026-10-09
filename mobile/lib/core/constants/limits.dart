library;

const double base64Inflation = 4.0 / 3.0;

const int maxSingleRecordBytes = 16 * 1024 * 1024;

const double nonBlobHeadroom = 0.75;

final int maxImageBlobBytes =
    ((maxSingleRecordBytes / base64Inflation) * nonBlobHeadroom).floor();

const int maxBatchPayloadBytes = 512 * 1024;

void validateLimits() {
  if (maxImageBlobBytes * base64Inflation >= maxSingleRecordBytes) {
    throw StateError(
      'maxImageBlobBytes exceeds maxSingleRecordBytes once base64-encoded.',
    );
  }
}
