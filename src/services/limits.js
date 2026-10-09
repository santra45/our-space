export const BASE64_INFLATION = 4 / 3;

export const MAX_SINGLE_RECORD_BYTES = 16 * 1024 * 1024;

const NON_BLOB_HEADROOM = 0.75;

export const MAX_IMAGE_BLOB_BYTES = Math.floor(
  (MAX_SINGLE_RECORD_BYTES / BASE64_INFLATION) * NON_BLOB_HEADROOM
);

export const MAX_BATCH_PAYLOAD_BYTES = 512 * 1024;

if (MAX_IMAGE_BLOB_BYTES * BASE64_INFLATION >= MAX_SINGLE_RECORD_BYTES) {
  throw new Error(
    'limits.js: MAX_IMAGE_BLOB_BYTES would not fit inside MAX_SINGLE_RECORD_BYTES once base64-encoded.'
  );
}
