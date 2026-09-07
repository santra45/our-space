/**
 * src/utils/imageCompression.js
 * Client-side photo compression for phone cameras.
 *
 * Resizes 12MP-50MP originals down to crisp retina images (~250KB) so AES-GCM
 * encryption and WebRTC transfers stay fast on mobile data.
 *
 * THREE THINGS THIS DELIBERATELY DOES NOT DO
 *
 * 1. It does not read the source through FileReader.readAsDataURL(). That
 *    inflates a 40MB original into a ~53MB base64 string in JS heap before the
 *    decoder ever sees it. createObjectURL() hands the decoder the bytes
 *    directly and costs nothing.
 *
 * 2. It does not produce a thumbnail. One was generated for years and consumed
 *    by nobody. Reviving it is not just a matter of storing it: peerSync's wire
 *    allowlist carries exactly one binary field for a memory (`imageBlob`), so a
 *    second blob would be stripped in transit and every synced photo would
 *    arrive thumbnail-less anyway. Encoding it was pure wasted main-thread time.
 *
 * 3. It never silently returns the untouched original. The old code did
 *    `fullBlob || file`, so a failed encode quietly shipped a 40MB raw HEIC that
 *    was then stored, encrypted, and finally mislabeled `image/webp` at decrypt
 *    time. A failure here now throws with a message worth showing a human.
 *
 * The mime of the produced blob is RETURNED, not assumed. Safari's toBlob()
 * ignores an unsupported request and silently hands back a PNG; callers must
 * persist the real type alongside the bytes so decryption can rebuild the Blob
 * correctly.
 */

/** Preferred output format: best size-per-quality of anything universally decodable. */
export const PREFERRED_IMAGE_MIME = 'image/webp';

/** Used when the browser cannot encode WebP, or encodes it into something bulkier. */
export const FALLBACK_IMAGE_MIME = 'image/jpeg';

/**
 * Compresses an image File or Blob using HTML5 Canvas.
 *
 * @param {File|Blob} file - The picked or captured original.
 * @param {Object} [options]
 * @param {number} [options.maxWidth=1440]
 * @param {number} [options.maxHeight=1440]
 * @param {number} [options.quality=0.85]
 * @returns {Promise<{ blob: Blob, mime: string, width: number, height: number, originalBytes: number }>}
 * @throws {Error} When the file is not a decodable image, or when the browser
 *   cannot re-encode it. Callers must surface the message rather than falling
 *   back to the original bytes.
 */
export async function compressImage(file, options = {}) {
  const maxWidth = options.maxWidth || 1440;
  const maxHeight = options.maxHeight || 1440;
  const quality = options.quality || 0.85;

  if (!file || typeof file !== 'object' || typeof file.size !== 'number') {
    throw new Error('No photo was selected.');
  }
  if (file.size === 0) {
    throw new Error('That file is empty.');
  }

  const img = await decodeImage(file);

  const sourceW = img.naturalWidth || img.width;
  const sourceH = img.naturalHeight || img.height;
  if (!sourceW || !sourceH) {
    throw new Error('That file could not be read as a photo.');
  }

  const { width, height } = calculateDimensions(sourceW, sourceH, maxWidth, maxHeight);

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;

  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('This browser blocked canvas rendering, so the photo cannot be compressed.');
  }
  ctx.drawImage(img, 0, 0, width, height);

  // Ask for WebP. A browser that cannot encode it either returns null or quietly
  // substitutes PNG - which for a photograph is several times LARGER than the
  // JPEG we would have asked for. Both cases fall through to JPEG.
  let blob = await canvasToBlob(canvas, PREFERRED_IMAGE_MIME, quality);
  if (!blob || blob.type !== PREFERRED_IMAGE_MIME) {
    const jpeg = await canvasToBlob(canvas, FALLBACK_IMAGE_MIME, quality);
    if (jpeg && jpeg.size > 0 && (!blob || jpeg.size < blob.size)) blob = jpeg;
  }

  if (!blob || blob.size === 0) {
    throw new Error('This browser could not re-encode the photo. Try a different image or browser.');
  }

  return {
    blob,
    mime: blob.type || FALLBACK_IMAGE_MIME,
    width,
    height,
    originalBytes: file.size,
  };
}

/**
 * Decodes a File into an <img> via an object URL.
 *
 * The URL is revoked as soon as the element reports it is loaded - the decoded
 * bitmap belongs to the element from that point on and does not need the URL to
 * stay alive. Using <img> rather than createImageBitmap() keeps EXIF orientation
 * handling, so portrait phone shots do not come out sideways.
 *
 * @param {File|Blob} file
 * @returns {Promise<HTMLImageElement>}
 */
function decodeImage(file) {
  return new Promise((resolve, reject) => {
    let url;
    try {
      url = URL.createObjectURL(file);
    } catch {
      reject(new Error('That file could not be opened.'));
      return;
    }

    const img = new Image();

    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('That file is not an image this browser can open.'));
    };

    img.src = url;
  });
}

/**
 * Promisified canvas.toBlob that resolves null instead of throwing, so the
 * caller can decide what an encode failure means.
 *
 * @param {HTMLCanvasElement} canvas
 * @param {string} mime
 * @param {number} quality
 * @returns {Promise<Blob|null>}
 */
function canvasToBlob(canvas, mime, quality) {
  return new Promise((resolve) => {
    try {
      canvas.toBlob((blob) => resolve(blob || null), mime, quality);
    } catch {
      resolve(null);
    }
  });
}

function calculateDimensions(srcW, srcH, maxW, maxH) {
  let width = srcW;
  let height = srcH;

  if (width > maxW) {
    height = Math.round((height * maxW) / width);
    width = maxW;
  }
  if (height > maxH) {
    width = Math.round((width * maxH) / height);
    height = maxH;
  }

  return { width: Math.max(1, width), height: Math.max(1, height) };
}
