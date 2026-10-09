export const PREFERRED_IMAGE_MIME = 'image/webp';

export const FALLBACK_IMAGE_MIME = 'image/jpeg';

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
