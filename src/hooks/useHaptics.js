/**
 * src/hooks/useHaptics.js
 * Tactile feedback for mobile Android devices using the Vibration API
 */
import { useCallback } from 'react';

export function useHaptics() {
  const trigger = useCallback((pattern) => {
    if (typeof window !== 'undefined' && 'navigator' in window && navigator.vibrate) {
      try {
        navigator.vibrate(pattern);
      } catch (e) {
        // Safe fail on unsupported browsers
      }
    }
  }, []);

  const tick = useCallback(() => trigger(10), [trigger]);
  const tap = useCallback(() => trigger(25), [trigger]);
  const celebration = useCallback(() => trigger([20, 50, 20, 50, 40]), [trigger]);
  const heartbeat = useCallback(() => trigger([60, 120, 60]), [trigger]);

  return { tick, tap, celebration, heartbeat };
}

export default useHaptics;
