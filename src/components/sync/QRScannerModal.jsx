/**
 * src/components/sync/QRScannerModal.jsx
 * In-app camera QR code scanner for Android devices using jsQR
 */
import React, { useRef, useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { X, Camera, RefreshCw } from 'lucide-react';
import jsQR from 'jsqr';
import { useHaptics } from '../../hooks/useHaptics';

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

    async function startCamera() {
      try {
        setCameraError(null);
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
        });

        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          videoRef.current.setAttribute('playsinline', 'true');
          await videoRef.current.play();
          requestAnimationFrame(scanQRCode);
        }
      } catch (err) {
        console.error('Camera access error:', err);
        setCameraError('Camera permission denied or camera not available.');
      }
    }

    function scanQRCode() {
      if (!isScanning) return;

      const video = videoRef.current;
      const canvas = canvasRef.current;

      if (video && video.readyState === video.HAVE_ENOUGH_DATA && canvas) {
        const ctx = canvas.getContext('2d');
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const code = jsQR(imageData.data, imageData.width, imageData.height, {
          inversionAttempts: 'dontInvert',
        });

        if (code && code.data) {
          isScanning = false;
          celebration();
          // Extract peer ID if it's a URL
          let detectedId = code.data;
          if (detectedId.includes('#connect=')) {
            detectedId = detectedId.split('#connect=')[1];
          }
          onScanSuccess(detectedId.trim());
          return;
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
      </motion.div>
    </div>
  );
}

export default QRScannerModal;
