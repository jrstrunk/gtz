import { Ok, Error, toList } from "./gleam.mjs";

export function local_timezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}

// Window over which offset transitions are materialized. It starts well before
// the tz database's own history does -- the earliest transition in the database
// is Pacific/Kosrae's in 1844, and the great majority of zones leave local mean
// time somewhere between then and 1912 -- so that a zone derived here holds the
// same transitions the Erlang target reads out of zoneinfo. Anchoring at the
// Unix epoch instead would be cheaper, but it would silently flatten every
// pre-1970 instant in 92% of zones onto the 1970 offset and disagree with the
// other target. Times before the window still resolve to the earliest known
// offset; there is simply nothing before 1800 to get wrong.
const TZDB_WINDOW_START = "1800-01-01T00:00:00Z";
const TZDB_WINDOW_END = "2100-01-01T00:00:00Z";
const WINDOW_START_SECONDS = Date.parse(TZDB_WINDOW_START) / 1000;
const WINDOW_END_SECONDS = Date.parse(TZDB_WINDOW_END) / 1000;

// Raw native transition facts for one IANA zone id, used by `gtz.build` to
// synthesize a lean tzif TzDatabase on the JavaScript target.
// Returns Gleam Result(List(#(Int, Int)), Nil) where each tuple is
//   #(transition_start_unix_seconds, utc_offset_seconds).
//
// `Temporal` reports transitions directly and is used where it exists. It is
// still absent from most shipping engines though (Node before 24, and every
// browser until very recently), so there is an `Intl` fallback that finds the
// same transitions by scanning. `Intl` has been universal for a decade.
export function zone_transitions(zoneId) {
  const cached = transitionCache.get(zoneId);
  if (cached !== undefined) {
    return cached;
  }

  const rows =
    typeof Temporal === "undefined"
      ? scanTransitionsWithIntl(zoneId)
      : temporalTransitions(zoneId);

  // Gleam values are immutable, so the same result can be handed out forever.
  // Deriving a zone costs tens of milliseconds on the Intl path and a program
  // will often rebuild the same one or two zones; the cache keeps that a
  // once-per-zone cost rather than a per-`build` one. Failures are cached too
  // so a typo'd zone name in a loop stays cheap.
  const result = rows === null ? new Error(undefined) : new Ok(toList(rows));
  transitionCache.set(zoneId, result);
  return result;
}

const transitionCache = new Map();

function temporalTransitions(zoneId) {
  const start = Temporal.Instant.from(TZDB_WINDOW_START);
  const end = Temporal.Instant.from(TZDB_WINDOW_END);

  let zdt;
  try {
    zdt = start.toZonedDateTimeISO(zoneId); // throws on an unknown zone id
  } catch (_e) {
    return null;
  }
  if (typeof zdt.getTimeZoneTransition !== "function") {
    // Temporal present but predates `getTimeZoneTransition`.
    return scanTransitionsWithIntl(zoneId);
  }

  const rows = [];
  // Baseline slice: the state in effect at the start of the window. It is
  // pushed first so it also serves as the database's pre-history default
  // (tzif's `default_slice` uses the first entry).
  rows.push(transitionRow(start.epochNanoseconds, zdt));

  let cursor = zdt;
  while (true) {
    const next = cursor.getTimeZoneTransition("next");
    if (next === null) break;
    if (Temporal.Instant.compare(next.toInstant(), end) > 0) break;
    rows.push(transitionRow(next.epochNanoseconds, next));
    cursor = next;
  }

  return rows;
}

function transitionRow(epochNanos, zdt) {
  const startSeconds = Number(epochNanos / 1_000_000_000n); // BigInt -> Int seconds
  const offsetSeconds = Math.round(zdt.offsetNanoseconds / 1_000_000_000);
  // A Gleam tuple is represented as a plain JS array.
  return [startSeconds, offsetSeconds];
}

// --- Intl fallback ---------------------------------------------------------

// How often the window is sampled while looking for offset changes. A
// transition can only be found if the offset differs at two adjacent samples,
// so the step has to be shorter than the briefest period a zone ever spends on
// one offset. The tightest cases in the database are 6.96 days: Brazil called
// off DST in Roraima a week after it began in October 2000 (America/Boa_Vista
// and neighbours), and Asia/Gaza's projected Ramadan pauses are the same width.
// A step of a week or more can straddle an island that narrow and miss both of
// its transitions, and whether it does depends on where the sample grid happens
// to fall. A day leaves nearly sevenfold margin, so nothing in the database or
// any plausible future entry slips between two samples, and the result does not
// depend on the grid's phase.
const SCAN_STEP_SECONDS = 24 * 60 * 60;

// Finds a zone's offset transitions using only `Intl`, by sampling the window
// and bisecting wherever the offset changed between two samples. Returns the
// same rows `temporalTransitions` does, or null for an unknown zone id.
function scanTransitionsWithIntl(zoneId) {
  let offsetAt;
  try {
    offsetAt = makeOffsetReader(zoneId); // throws on an unknown zone id
  } catch (_e) {
    return null;
  }

  // Baseline slice: the state in effect at the start of the window. It is
  // pushed first so it also serves as the database's pre-history default
  // (tzif's `default_slice` uses the first entry).
  let previousOffset = offsetAt(WINDOW_START_SECONDS);
  // A Gleam tuple is represented as a plain JS array.
  const rows = [[WINDOW_START_SECONDS, previousOffset]];

  let previous = WINDOW_START_SECONDS;
  for (
    let current = WINDOW_START_SECONDS + SCAN_STEP_SECONDS;
    current <= WINDOW_END_SECONDS;
    current += SCAN_STEP_SECONDS
  ) {
    const offset = offsetAt(current);
    if (offset !== previousOffset) {
      // The change happened somewhere in (previous, current]; bisect for the
      // first second that reports the new offset.
      let low = previous;
      let high = current;
      while (high - low > 1) {
        const middle = low + Math.floor((high - low) / 2);
        if (offsetAt(middle) === previousOffset) {
          low = middle;
        } else {
          high = middle;
        }
      }
      rows.push([high, offset]);
      previousOffset = offset;
    }
    previous = current;
  }

  return rows;
}

// Builds a function from Unix seconds to the zone's UTC offset in seconds. The
// formatter is created once per zone because constructing one is by far the
// expensive part, and the scan above calls this thousands of times.
function makeOffsetReader(zoneId) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: zoneId,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });

  // `format` is around three times faster than `formatToParts`, which matters
  // over thousands of samples, but it returns one string. Rather than assume a
  // punctuation layout, learn the order the numeric fields come out in from a
  // single `formatToParts` probe, then just pull the numbers out of each
  // formatted string in that order.
  const fieldOrder = formatter
    .formatToParts(new Date(0))
    .map((part) => part.type)
    .filter((type) => type !== "literal");

  return (epochSeconds) => {
    const date = new Date(epochSeconds * 1000);
    const numbers = formatter.format(date).match(/\d+/g);

    const parts = {};
    if (numbers !== null && numbers.length === fieldOrder.length) {
      fieldOrder.forEach((type, index) => (parts[type] = numbers[index]));
    } else {
      // Unexpected shape from this engine; pay for the reliable path instead.
      for (const part of formatter.formatToParts(date)) {
        parts[part.type] = part.value;
      }
    }

    // Some engines render midnight as hour 24 rather than 00.
    const hour = parts.hour === "24" ? 0 : Number(parts.hour);

    // Reading the local wall clock time back as if it were UTC gives an
    // instant that differs from the real one by exactly the zone's offset.
    const asUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      hour,
      Number(parts.minute),
      Number(parts.second),
    );

    return Math.round(asUtc / 1000) - epochSeconds;
  };
}
