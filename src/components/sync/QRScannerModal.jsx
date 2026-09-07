/**
 * src/components/sync/QRScannerModal.jsx
 * In-app camera QR code scanner for Android devices using jsQR.
 *
 * Two things this file has to get right:
 *  - Cost. jsQR runs on the main thread, so the frame it is handed is downscaled
 *    to SCAN_MAX_DIMENSION and only sampled SCAN_INTERVAL_MS apart. Decoding a
 *    12MP frame 60 times a second locks up a phone for no extra accuracy.
 *  - Handing the payload over intact. The QR encodes a full invite URL with a
 *    salt and other params; splitting it by hand mangles it. `parseInvite` is
 *    the single parser and the raw scanned string is what gets forwarded on.
 */
import React, { useRef, useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { X } from 'lucide-react';
import jsQR from 'jsqr';
import { parseInvite } from '../../utils/invite';
import { useHaptics } from '../../hooks/useHaptics';

/** Longest edge of the buffer jsQR actually scans. QR codes decode fine here. */
const SCAN_MAX_DIMENSION = 640;
/** ~10fps. Anything faster just burns battery on the same frame. */
const SCAN_INTERVAL_MS = 100;

export function QRScannerModal({ isOpen, onClose, onScanSuccess }) {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const [cameraError, setCameraError] = useState(null);
  const { tap, celebration } = useHaptics();

  useEffect(() => {
    if (!isOpen) return;

    let stream = null;
    let animationFrameId = null;
    let isScanning = true;
    let lastScanAt = 0;
    let scanWidth = 0;
    let scanHeight = 0;

    async function startCamera() {
      try {
        setCameraError(null);
        const media = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
        });

        // The modal can close (or a scan can succeed) while the permission
        // prompt is still up. Cleanup already ran and saw a null stream, so the
        // camera would stay live with its LED on until the tab died.
        if (!isScanning) {
          media.getTracks().forEach((track) => track.stop());
          return;
        }

        stream = media;

        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          videoRef.current.setAttribute('playsinline', 'true');
          await videoRef.current.play();
          animationFrameId = requestAnimationFrame(scanQRCode);
        }
      } catch {
        setCameraError('Camera permission denied or camera not available.');
      }
    }

    /** Sizes the scan buffer once per resolution change, not once per frame. */
    function syncCanvasSize(canvas, video) {
      const sourceWidth = video.videoWidth;
      const sourceHeight = video.videoHeight;
      if (!sourceWidth || !sourceHeight) return false;

      const scale = Math.min(1, SCAN_MAX_DIMENSION / Math.max(sourceWidth, sourceHeight));
      const width = Math.max(1, Math.round(sourceWidth * scale));
      const height = Math.max(1, Math.round(sourceHeight * scale));

      if (width !== scanWidth || height !== scanHeight) {
        scanWidth = width;
        scanHeight = height;
        // Assigning width/height clears the canvas, so only do it on a change.
        canvas.width = width;
        canvas.height = height;
      }
      return true;
    }

    function scanQRCode(timestamp) {
      if (!isScanning) return;

      const now = typeof timestamp === 'number' ? timestamp : performance.now();
      if (now - lastScanAt >= SCAN_INTERVAL_MS) {
        lastScanAt = now;

        const video = videoRef.current;
        const canvas = canvasRef.current;

        if (video && canvas && video.readyState === video.HAVE_ENOUGH_DATA) {
          if (syncCanvasSize(canvas, video)) {
            const ctx = canvas.getContext('2d', { willReadFrequently: true });
            ctx.drawImage(video, 0, 0, scanWidth, scanHeight);

            const imageData = ctx.getImageData(0, 0, scanWidth, scanHeight);
            const code = jsQR(imageData.data, imageData.width, imageData.height, {
              inversionAttempts: 'dontInvert',
            });

            const payload = code && code.data ? code.data.trim() : '';
            // Validate, but forward the ORIGINAL string: the invite carries the
            // vault salt and pairing metadata alongside the peer id.
            if (payload && parseInvite(payload)?.partnerPeerId) {
              isScanning = false;
              celebration();
              onScanSuccess(payload);
              return;
            }
          }
        }
      }

      animationFrameId = requestAnimationFrame(scanQRCode);
    }

    startCamera();

    return () => {
      isScanning = false;
      if (animationFrameId) cancelAnimationFrame(animationFrameId);
      if (stream) {
        stream.getTracks().forEach((track) => track.stop());
        stream = null;
      }
    };
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        className="w-full max-w-sm bg-slate-900 rounded-3xl p-5 text-white relative overflow-hidden"
      >
        <button
          onClick={() => {
            tap();
            onClose();
          }}
          className="absolute top-4 right-4 w-8 h-8 rounded-full bg-white/20 text-white flex items-center justify-center hover:bg-white/30"
        >
          <X className="w-4 h-4" />
        </button>

        <div className="text-center mb-4">
          <h3 className="text-base font-bold">Scan Partner's QR</h3>
          <p className="text-xs text-slate-400">Point your camera at her screen to pair</p>
        </div>

        {cameraError ? (
          <div className="p-4 bg-rose-500/20 border border-rose-500/40 rounded-2xl text-xs text-rose-300 text-center">
            {cameraError}
          </div>
        ) : (
          <div className="relative aspect-square rounded-2xl overflow-hidden bg-black border-2 border-blush-400">
            <video ref={videoRef} className="w-full h-full object-cover" />
            <canvas ref={canvasRef} className="hidden" />

            {/* Target reticle */}
            <div className="absolute inset-8 border-2 border-dashed border-white/60 rounded-2xl pointer-events-none animate-pulse" />
          </div>
        )}

        <p className="mt-3 text-[10px] text-slate-500 text-center leading-relaxed">
          Scanning stays on this device. Nothing is uploaded.
        </p>
      </motion.div>
    </div>
  );
}

export default QRScannerModal;
