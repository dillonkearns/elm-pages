// --- Timezone helpers ---

const TWO_WEEKS_MS = 14 * 24 * 60 * 60 * 1000;

/**
 * Handle elm-pages-internal://timezone requests.
 * Accepts { sinceMs, untilMs } for the date range to scan for DST transitions.
 * Optionally accepts { tzId } for a named timezone; defaults to system timezone.
 * Returns { defaultOffset, eras } for Time.customZone.
 */
export function runTimezone(req) {
  const body = req.body.args[0];
  const tzId = body.tzId || Intl.DateTimeFormat().resolvedOptions().timeZone;

  // Validate timezone name by attempting a format
  try {
    Intl.DateTimeFormat("en-US", { timeZone: tzId });
  } catch (e) {
    throw {
      title: "Invalid Timezone",
      message: `"${tzId}" is not a valid IANA timezone identifier.\n\nExamples of valid identifiers: "America/New_York", "Europe/London", "Asia/Tokyo", "UTC".`,
    };
  }

  const { sinceMs, untilMs } = body;

  if (supportsTemporalTransitions()) {
    return getTimezoneDataTemporal(tzId, sinceMs, untilMs);
  }
  return getTimezoneDataIntl(tzId, sinceMs, untilMs);
}

/**
 * Cache Intl.DateTimeFormat instances for performance.
 * Using formatToParts + cached formatters is ~10x faster than toLocaleString re-parsing.
 */
const tzFormatters = new Map();
const utcFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: "UTC",
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "numeric",
  second: "numeric",
  hour12: false,
});

function getTzFormatter(tzId) {
  let fmt = tzFormatters.get(tzId);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: tzId,
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      hour12: false,
    });
    tzFormatters.set(tzId, fmt);
  }
  return fmt;
}

function partsToMs(parts) {
  const p = {};
  for (const { type, value } of parts) p[type] = parseInt(value) || 0;
  const h = p.hour === 24 ? 0 : p.hour;
  return Date.UTC(p.year, p.month - 1, p.day, h, p.minute, p.second);
}

/**
 * Get UTC offset in minutes for a timezone at a given instant.
 */
function getOffsetMinutesIntl(tzId, ms) {
  const utcMs = partsToMs(utcFormatter.formatToParts(ms));
  const localMs = partsToMs(getTzFormatter(tzId).formatToParts(ms));
  return (localMs - utcMs) / 60000;
}

/**
 * Binary search to find the exact minute when a timezone offset transition occurs.
 */
function binarySearchTransition(tzId, loMs, hiMs, offsetBefore) {
  while (hiMs - loMs > 60000) {
    const mid = Math.floor((loMs + hiMs) / 2);
    if (getOffsetMinutesIntl(tzId, mid) === offsetBefore) {
      loMs = mid;
    } else {
      hiMs = mid;
    }
  }
  return hiMs;
}

/**
 * Get timezone transition data using the Intl API (scan + binary search).
 * Scans every 2 weeks to catch even rare mid-month transitions.
 */
export function getTimezoneDataIntl(tzId, sinceMs, untilMs) {
  const defaultOffset = getOffsetMinutesIntl(tzId, sinceMs);
  const eras = [];
  let prevOffset = defaultOffset;

  let scanMs = sinceMs + TWO_WEEKS_MS;
  while (scanMs <= untilMs) {
    const offset = getOffsetMinutesIntl(tzId, scanMs);
    if (offset !== prevOffset) {
      const exactMs = binarySearchTransition(
        tzId,
        scanMs - TWO_WEEKS_MS,
        scanMs,
        prevOffset
      );
      eras.push({
        start: Math.floor(exactMs / 60000),
        offset: offset,
      });
      prevOffset = offset;
    }
    scanMs += TWO_WEEKS_MS;
  }

  // elm/time expects eras sorted newest-first
  eras.reverse();
  return { defaultOffset, eras };
}

/**
 * The final Temporal API (shipped in Node 26) finds transitions through
 * ZonedDateTime. Earlier drafts and older polyfills used Temporal.TimeZone,
 * which was removed, so those fall back to the Intl scan.
 */
function supportsTemporalTransitions() {
  const Temporal = globalThis.Temporal;
  return (
    typeof Temporal !== "undefined" &&
    typeof Temporal.Instant?.fromEpochMilliseconds === "function" &&
    typeof Temporal.ZonedDateTime?.prototype?.getTimeZoneTransition ===
      "function"
  );
}

/**
 * Get timezone transition data using the Temporal API (direct transition walking).
 */
export function getTimezoneDataTemporal(tzId, sinceMs, untilMs) {
  const Temporal = globalThis.Temporal;
  const start =
    Temporal.Instant.fromEpochMilliseconds(sinceMs).toZonedDateTimeISO(tzId);

  const defaultOffset = start.offsetNanoseconds / 60_000_000_000;
  const eras = [];
  let prevOffset = defaultOffset;

  let transition = start.getTimeZoneTransition("next");
  while (transition && transition.epochMilliseconds < untilMs) {
    const offset = transition.offsetNanoseconds / 60_000_000_000;
    if (offset !== prevOffset) {
      eras.push({
        start: Math.floor(transition.epochMilliseconds / 60000),
        offset: offset,
      });
      prevOffset = offset;
    }
    transition = transition.getTimeZoneTransition("next");
  }

  // elm/time expects eras sorted newest-first
  eras.reverse();
  return { defaultOffset, eras };
}
