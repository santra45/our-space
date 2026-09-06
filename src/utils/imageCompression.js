/**
 * src/utils/imageCompression.js
 * Client-side photo compression for Android cameras.
 * Resizes 12MP-50MP mobile photos down to crisp retina WebP images (~250KB)
 * to ensure lightning-fast AES-GCM encryption and WebRTC transfers over mobile data.
 */

/**
 * Compresses an image File or Blob using HTML5 Canvas.
 * @param {File|Blob} file 
 * @param {Object} options 
 * @returns {Promise<{ fullBlob: Blob, thumbnailBlob: Blob }>}
 */
export async function compressImage(file, options = {}) {
  const maxWidth = options.maxWidth || 1440;
  const maxHeight = options.maxHeight || 1440;
  const quality = options.quality || 0.85;

  const thumbMaxWidth = options.thumbMaxWidth || 320;
  const thumbMaxHeight = options.thumbMaxHeight || 320;
  const thumbQuality = options.thumbQuality || 0.7;

  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = reject;
    reader.onload = () => {
      const img = new Image();
      img.onerror = reject;
      img.onload = () => {
        // 1. Generate Full-size compressed image
        const { width: fullW, height: fullH } = calculateDimensions(img.width, img.height, maxWidth, maxHeight);
        const fullCanvas = document.createElement('canvas');
        fullCanvas.width = fullW;
        fullCanvas.height = fullH;
        const fullCtx = fullCanvas.getContext('2d');
        fullCtx.drawImage(img, 0, 0, fullW, fullH);

        // 2. Generate small thumbnail for instant masonry loading
        const { width: thumbW, height: thumbH } = calculateDimensions(img.width, img.height, thumbMaxWidth, thumbMaxHeight);
        const thumbCanvas = document.createElement('canvas');
        thumbCanvas.width = thumbW;
        thumbCanvas.height = thumbH;
        const thumbCtx = thumbCanvas.getContext('2d');
        thumbCtx.drawImage(img, 0, 0, thumbW, thumbH);

        // Determine mime type (prefer WebP on Android, fallback to JPEG)
        const format = 'image/webp';

        fullCanvas.toBlob(
          (fullBlob) => {
            thumbCanvas.toBlob(
              (thumbBlob) => {
                resolve({
                  fullBlob: fullBlob || file,
                  thumbnailBlob: thumbBlob || fullBlob || file,
                  width: fullW,
                  height: fullH,
                });
              },
              format,
              thumbQuality
            );
          },
          format,
          quality
        );
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
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

  return { width, height };
}
