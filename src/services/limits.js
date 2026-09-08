/**
 * src/services/limits.js
 * Size ceilings shared by local storage and the sync wire.
 *
 * WHY THIS FILE EXISTS
 * These limits used to live where they were enforced: the photo ceiling in
 * db/index.js, the record and batch ceilings in peerSync.js. Nothing tied them
 * together, and they drifted - a photo was accepted locally at up to 32MB while
 * the wire refused anything over 16MB. The blob is base64'd on its way out, so
 * the real cutoff was around 12MB of raw bytes, and everything above it saved
 * happily to this phone and could then NEVER reach the partner. The failure was
 * silent and permanent: no error at save time, and the record was rejected on
 * every sync attempt forever after.
 *
 * peerSync already imports db/index.js, so the limits could not simply live in
 * one of them without an import cycle. They live here instead, and the local
 * ceiling is DERIVED from the wire ceiling rather than written down twice, so
 * the two cannot drift apart again.
 */

/**
 * Base64 turns 3 bytes into 4 characters. A blob is base64'd by _toWireRecord()
 * before its size is measured, so any raw byte count must be multiplied by this
 * to predict what the wire will see.
 */
export const BASE64_INFLATION = 4 / 3;

/**
 * Ceiling on a SINGLE record, measured on the serialized wire record (i.e.
 * AFTER the blob has been base64'd). A record over this can never be framed, so
 * it is reported to both sides rather than silently dropped forever.
 */
export const MAX_SINGLE_RECORD_BYTES = 16 * 1024 * 1024;

/**
 * Headroom left for everything in a record that is not the photo: the encrypted
 * envelope, the id, the timestamps, the JSON punctuation. 0.75 is deliberately
 * generous - being conservative here costs a little photo resolution, while
 * being wrong costs a memory that silently never syncs.
 */
const NON_BLOB_HEADROOM = 0.75;

/**
 * Ceiling on a photo's encrypted bytes as stored locally.
 *
 * Derived, not chosen: a blob at this size base64s to well inside
 * MAX_SINGLE_RECORD_BYTES, so anything this phone accepts is guaranteed to fit
 * on the wire. Works out to 9MB at the current wire limit.
 */
export const MAX_IMAGE_BLOB_BYTES = Math.floor(
  (MAX_SINGLE_RECORD_BYTES / BASE64_INFLATION) * NON_BLOB_HEADROOM
);

/**
 * Budget for ONE outbound SYNC_RECORDS_BATCH, measured on the serialized record
 * payload before encryption.
 *
 * Base64 + AES-GCM inflates roughly 1.34x, so 8MB of records lands near 11MB of
 * ciphertext - under the 30MB inbound cap.
 */
export const MAX_BATCH_PAYLOAD_BYTES = 8 * 1024 * 1024;

/**
 * Guard against a future edit reintroducing the drift this file exists to stop.
 * Cheap enough to run at module load, and it fails loudly rather than shipping
 * a photo ceiling that silently cannot sync.
 */
if (MAX_IMAGE_BLOB_BYTES * BASE64_INFLATION >= MAX_SINGLE_RECORD_BYTES) {
  throw new Error(
    'limits.js: MAX_IMAGE_BLOB_BYTES would not fit inside MAX_SINGLE_RECORD_BYTES once base64-encoded.'
  );
}
