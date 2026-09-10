/**
 * src/components/common/ConfettiBurst.jsx
 * Celebratory heart and pastel confetti bursts.
 *
 * WHY THIS DOES NOT USE canvas-confetti's DEFAULT EXPORT
 * The default `confetti()` is created internally with `useWorker: true`, which
 * renders inside a Web Worker built from a `blob:` URL. Our CSP sets
 * `worker-src 'self'`, so the browser blocks that worker - and the failure is
 * silent in the worst possible way: in Chromium the `new Worker(blob:...)` call
 * does NOT throw, so canvas-confetti's own try/catch never fires. It hands the
 * canvas to a worker that will never run a single frame. The canvas is created,
 * sized and attached, nothing is ever drawn on it, and no error surfaces. That
 * is exactly what "the button works but no confetti appears" looked like.
 *
 * `useWorker` is a CREATION option, not a per-call one, so the fix is our own
 * instance. Rendering moves to the main thread, which for a few seconds of
 * particles is not a cost worth loosening the CSP over.
 */
import confetti from 'canvas-confetti';

const CANVAS_ID = 'our-space-confetti';

/** Lazily created worker-free confetti instance, bound to our own canvas. */
let cannon = null;

function getCannon() {
  if (cannon) return cannon;
  if (typeof document === 'undefined') return null;

  let canvas = document.getElementById(CANVAS_ID);
  if (!canvas) {
    canvas = document.createElement('canvas');
    canvas.id = CANVAS_ID;
    // Full-viewport overlay that never intercepts a tap. z-index sits above the
    // modals (z-50) so a burst fired from inside one is still visible.
    Object.assign(canvas.style, {
      position: 'fixed',
      top: '0',
      left: '0',
      width: '100%',
      height: '100%',
      pointerEvents: 'none',
      zIndex: '100',
    });
    document.body.appendChild(canvas);
  }

  cannon = confetti.create(canvas, { resize: true, useWorker: false });
  return cannon;
}

export function fireHeartConfetti() {
  const fire = getCannon();
  if (!fire) return;

  const heartShape = confetti.shapeFromPath({
    path: 'M167 72c19,-38 37,-56 75,-56 42,0 76,33 76,75 0,76 -76,151 -151,227 -76,-76 -151,-151 -151,-227 0,-42 33,-75 76,-75 38,0 57,18 75,56z',
  });

  fire({
    shapes: [heartShape, 'circle'],
    particleCount: 50,
    spread: 70,
    origin: { y: 0.7 },
    colors: ['#ff85a3', '#ff5480', '#ffd1dc', '#cdbeff', '#f9f1dc'],
    scalar: 1.2,
  });
}

export function fireCelebrationBurst() {
  const cannonFire = getCannon();
  if (!cannonFire) return;

  const count = 150;
  const defaults = {
    origin: { y: 0.7 },
    colors: ['#ff85a3', '#ff5480', '#b196ff', '#cbdec8', '#ffd1dc'],
  };

  function fire(particleRatio, opts) {
    cannonFire({
      ...defaults,
      ...opts,
      particleCount: Math.floor(count * particleRatio),
    });
  }

  fire(0.25, { spread: 26, startVelocity: 55 });
  fire(0.2, { spread: 60 });
  fire(0.35, { spread: 100, decay: 0.91, scalar: 0.8 });
  fire(0.1, { spread: 120, startVelocity: 25, decay: 0.92, scalar: 1.2 });
  fire(0.1, { spread: 120, startVelocity: 45 });
}
