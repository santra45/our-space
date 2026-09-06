/**
 * src/hooks/useLiveCounter.js
 * Precision timer hook for real-time live relationship duration
 */
import { useState, useEffect } from 'react';
import { calculateLoveDuration } from '../utils/dateHelpers';

export function useLiveCounter(startDateStr) {
  const [duration, setDuration] = useState(() => calculateLoveDuration(startDateStr));

  useEffect(() => {
    if (!startDateStr) return;

    setDuration(calculateLoveDuration(startDateStr));

    const interval = setInterval(() => {
      setDuration(calculateLoveDuration(startDateStr));
    }, 1000);

    return () => clearInterval(interval);
  }, [startDateStr]);

  return duration;
}

export default useLiveCounter;
