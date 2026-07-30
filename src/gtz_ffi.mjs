import { Ok, Error, toList } from "./gleam.mjs";

export function is_valid_timezone(timeZone) {
  try {
    Intl.DateTimeFormat(undefined, {timeZone: timeZone});
    return true;
  } catch (error) {
    return false;
  }
}

export function calculate_offset(year, month, day, hour, minute, second, timezone) {
  // Create Date objects for UTC and the target timezone
  // const utcDate = new Date(unix_timestamp * 1000);
  const utcDate = new Date(Date.UTC(year, month - 1, day, hour, minute, second));

  // Format options for getting the time components
  const options = {
    timeZone: timezone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  };

  // Format the date in the target timezone
  const formatter = new Intl.DateTimeFormat('en-US', options);
  const parts = formatter.formatToParts(utcDate);

  // For some reason the formatter was formatting times with the hour 00 as 24,
  // so if that is the case we can manually set it to 00.
  let hourValue = parts.find(p => p.type === 'hour').value
  hourValue = hourValue == '24' ? '00' : hourValue

  const targetDateStr = `${parts.find(p => p.type === 'year').value}-${parts.find(p => p.type === 'month').value}-${parts.find(p => p.type === 'day').value}T${hourValue}:${parts.find(p => p.type === 'minute').value}:${parts.find(p => p.type === 'second').value}`;
  const utcDateStr = utcDate.toISOString().slice(0, 19);

  // Calculate the difference in the unix timestamps
  const targetTime = new Date(targetDateStr).getTime();
  const utcTime = new Date(utcDateStr).getTime();

  return Math.trunc((targetTime - utcTime) / 60000);
}

export function local_timezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}

// Reported to Gleam as `is_javascript()`; the Erlang fallback returns False.
export function is_javascript() {
  return true;
}

// Window over which offset transitions are materialized. It starts at the Unix
// epoch on purpose: this covers every realistic `gleam_time` timestamp, and it
// keeps the `is_dst` heuristic honest. Including pre-modern local-mean-time
// offsets (which are often smaller than a zone's modern standard offset) would
// make that standard offset look "raised" and be mislabeled as DST -- e.g.
// Asia/Kolkata's +5:30. Widen the start if you truly need pre-1970 history, at
// the cost of that heuristic accuracy. Times before the window resolve to the
// earliest known offset.
const TZDB_WINDOW_START = "1970-01-01T00:00:00Z";
const TZDB_WINDOW_END = "2100-01-01T00:00:00Z";

// Raw native transition facts for one IANA zone id, used by `gtz.load` to
// synthesize a lean tzif TzDatabase on the JavaScript target.
// Returns Gleam Result(List(#(Int, Int, String)), Nil) where each tuple is
//   #(transition_start_unix_seconds, utc_offset_seconds, designation).
export function zone_transitions(zoneId) {
  if (typeof Temporal === "undefined") {
    return new Error(undefined);
  }

  const start = Temporal.Instant.from(TZDB_WINDOW_START);
  const end = Temporal.Instant.from(TZDB_WINDOW_END);

  let zdt;
  try {
    zdt = start.toZonedDateTimeISO(zoneId); // throws on an unknown zone id
  } catch (_e) {
    return new Error(undefined);
  }
  if (typeof zdt.getTimeZoneTransition !== "function") {
    return new Error(undefined); // Temporal present but too old
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

  return new Ok(toList(rows));
}

function transitionRow(epochNanos, zdt) {
  const startSeconds = Number(epochNanos / 1_000_000_000n); // BigInt -> Int seconds
  const offsetSeconds = Math.round(zdt.offsetNanoseconds / 1_000_000_000);
  // A Gleam tuple is represented as a plain JS array.
  return [startSeconds, offsetSeconds, zoneAbbreviation(zdt)];
}

// Best-effort zone abbreviation. Yields "EDT" and friends where the locale data
// has one, otherwise a numeric form such as "GMT-4". This is the documented
// approximation for `designation`.
function zoneAbbreviation(zdt) {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: zdt.timeZoneId,
    timeZoneName: "short",
    year: "numeric",
  });
  const part = fmt
    .formatToParts(new Date(zdt.epochMilliseconds))
    .find((p) => p.type === "timeZoneName");
  return part ? part.value : "";
}
