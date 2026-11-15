/**
 * Turn calls that come close together into one.
 *
 * The function runs once the calls have stopped coming for `quietMs`. If they
 * never stop, it still runs `atMost` milliseconds after the first one.
 *
 * @param {() => void} run
 * @param {number} quietMs
 * @param {{ atMost?: number }} [options]
 * @returns {() => void}
 */
export function coalesce(run, quietMs, { atMost = quietMs * 10 } = {}) {
  /** @type {ReturnType<typeof setTimeout> | null} */
  let timer = null;
  let firstCallAt = 0;

  return function () {
    const now = Date.now();
    if (timer === null) {
      firstCallAt = now;
    } else {
      clearTimeout(timer);
    }
    const wait = Math.max(0, Math.min(quietMs, firstCallAt + atMost - now));
    timer = setTimeout(() => {
      timer = null;
      run();
    }, wait);
  };
}
