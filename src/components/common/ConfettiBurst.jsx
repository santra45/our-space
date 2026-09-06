/**
 * src/components/common/ConfettiBurst.jsx
 * Celebratory heart and pastel confetti bursts
 */
import confetti from 'canvas-confetti';

export function fireHeartConfetti() {
  const heartShape = confetti.shapeFromPath({
    path: 'M167 72c19,-38 37,-56 75,-56 42,0 76,33 76,75 0,76 -76,151 -151,227 -76,-76 -151,-151 -151,-227 0,-42 33,-75 76,-75 38,0 57,18 75,56z',
  });

  confetti({
    shapes: [heartShape, 'circle'],
    particleCount: 50,
    spread: 70,
    origin: { y: 0.7 },
    colors: ['#ff85a3', '#ff5480', '#ffd1dc', '#cdbeff', '#f9f1dc'],
    scalar: 1.2,
  });
}

export function fireCelebrationBurst() {
  const count = 150;
  const defaults = {
    origin: { y: 0.7 },
    colors: ['#ff85a3', '#ff5480', '#b196ff', '#cbdec8', '#ffd1dc'],
  };

  function fire(particleRatio, opts) {
    confetti({
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
