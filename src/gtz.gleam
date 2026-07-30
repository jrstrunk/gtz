//// Functions to provide simple timezone support for other Gleam datetime libraries.

import gleam/list
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import tempo
import tempo/naive_datetime
import tempo/offset
import tzif/database.{type TzDatabase}
import tzif/parser

/// Constructs a TimeZoneProvider type to be used with the Tempo package.
/// Returns an error if the timezone is not valid.
///
/// ## Examples
///
/// ```gleam
/// import tempo/datetime
///
/// let assert Ok(tz) = gtz.timezone("America/New_York")
///
/// datetime.literal("2024-06-21T06:30:02.334Z")
/// |> datetime.to_timezone(tz)
/// |> datetime.to_string
/// // -> "2024-01-03T02:30:02.334-04:00"
/// ```
pub fn timezone(name: String) -> Result(tempo.TimeZoneProvider, Nil) {
  case is_valid_timezone(name) {
    True ->
      Ok(
        tempo.TimeZoneProvider(
          get_name: fn() { name },
          calculate_offset: fn(utc_naive_datetime) {
            let #(#(year, month, day), #(hour, minute, second)) =
              naive_datetime.to_tuple(utc_naive_datetime)

            let assert Ok(offset) =
              calculate_offset_ffi(year, month, day, hour, minute, second, name)
              |> duration.minutes
              |> offset.from_duration

            offset
          },
        ),
      )
    False -> Error(Nil)
  }
}

/// Calculates the offset of a given timestamp in a specific time zone. Returns
/// an error if the time zone is invalid.
///
/// This can be combined with the `gleam_time` package to convert timestamps to
/// calendar dates in a given time zone.
///
/// ## Example
///
/// ```gleam
/// import gtz
/// import gleam/time/timestamp
///
/// let my_ts =
///   1_729_257_776
///   |> timestamp.from_unix_seconds
///
/// let assert Ok(offset) =
///   gtz.calculate_offset(my_ts, in: "America/New_York")
///
/// timestamp.to_calendar(my_ts, offset)
/// // -> #(
/// //   calendar.Date(2024, calendar.October, 18),
/// //   calendar.TimeOfDay(9, 22, 56, 0)
/// // )
/// ```
pub fn calculate_offset(
  timestamp: timestamp.Timestamp,
  in time_zone: String,
) -> Result(duration.Duration, Nil) {
  case is_valid_timezone(time_zone) {
    True -> {
      let #(
        calendar.Date(year:, month:, day:),
        calendar.TimeOfDay(hours:, minutes:, seconds:, nanoseconds: _),
      ) = timestamp.to_calendar(timestamp, calendar.utc_offset)

      calculate_offset_ffi(
        year,
        month |> calendar.month_to_int,
        day,
        hours,
        minutes,
        seconds,
        time_zone,
      )
      |> duration.minutes
      |> Ok
    }
    False -> Error(Nil)
  }
}

/// The offset from UTC, in minutes, that `timezone` was at the given UTC
/// wall-clock time. On JavaScript this is answered by the host's `Intl` API; on
/// Erlang it comes from the operating system's TZif database via `tzif`.
///
/// An unknown zone yields 0, which callers never observe because every entry
/// point checks `is_valid_timezone` first.
fn calculate_offset_ffi(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
  timezone: String,
) -> Int {
  case is_javascript() {
    True ->
      calculate_offset_js(year, month, day, hour, minute, second, timezone)
    False ->
      case
        os_zone_parameters(year, month, day, hour, minute, second, timezone)
      {
        Ok(params) -> {
          let #(seconds, _nanoseconds) =
            duration.to_seconds_and_nanoseconds(params.offset)
          seconds / 60
        }
        Error(_) -> 0
      }
  }
}

fn os_zone_parameters(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
  timezone: String,
) -> Result(database.ZoneParameters, Nil) {
  use db <- result.try(os_database())
  use month <- result.try(calendar.month_from_int(month))

  let timestamp =
    timestamp.from_calendar(
      calendar.Date(year:, month:, day:),
      calendar.TimeOfDay(
        hours: hour,
        minutes: minute,
        seconds: second,
        nanoseconds: 0,
      ),
      calendar.utc_offset,
    )

  database.get_zone_parameters(timestamp, timezone, db)
  |> result.replace_error(Nil)
}

fn is_valid_timezone(timezone: String) -> Bool {
  case is_javascript() {
    True -> is_valid_timezone_js(timezone)
    False ->
      case os_database() {
        Ok(db) ->
          database.get_available_timezones(db) |> list.contains(timezone)
        Error(_) -> False
      }
  }
}

// External on JavaScript; the Gleam bodies below are the Erlang fallbacks and
// are never reached there because the callers above branch on `is_javascript`.
@external(javascript, "./gtz_ffi.mjs", "calculate_offset")
fn calculate_offset_js(
  _year: Int,
  _month: Int,
  _day: Int,
  _hour: Int,
  _minute: Int,
  _second: Int,
  _timezone: String,
) -> Int {
  0
}

@external(javascript, "./gtz_ffi.mjs", "is_valid_timezone")
fn is_valid_timezone_js(_timezone: String) -> Bool {
  False
}

// The host's TZif database, loaded once and memoized. External on Erlang; the
// Gleam body is the JavaScript fallback, where there is no filesystem to read
// TZif files from.
@external(erlang, "gtz_ffi", "os_database")
fn os_database() -> Result(TzDatabase, Nil) {
  Error(Nil)
}

/// Returns the name of the host system's timezone.
///
/// ## Examples
///
/// ```gleam
/// gtz.local_name()
/// // -> "Europe/London"
/// ```
///
/// On the Erlang target the zone is read from the operating system, in order:
/// the `TZ` environment variable, the symlink target of `/etc/localtime`, then
/// `/etc/timezone` or `/etc/sysconfig/clock`. If none of those yield an IANA
/// zone name, `"UTC"` is returned. On JavaScript the host's `Intl` API is used.
@external(erlang, "gtz_ffi", "local_timezone")
@external(javascript, "./gtz_ffi.mjs", "local_timezone")
pub fn local_name() -> String

/// Obtain a `tzif` `TzDatabase` covering the given IANA zone names.
///
/// This provides the richer `tzif/database` and `tzif/tzcalendar` API (offset,
/// designation, is-DST, ambiguous/skipped wall-clock times, ...) rather than
/// just an offset, and works on both targets:
///
/// - On **Erlang** the full IANA database is loaded from the operating
///   system's TZif files via `tzif`'s `database.load_from_os`, so `zone_names`
///   is ignored and every installed zone is available. This includes leap
///   second data where the OS provides it.
/// - On **JavaScript**, where there is no filesystem to read TZif files from, a
///   lean database is synthesized on the fly from the host's native time zone
///   engine (the `Temporal` API plus `Intl`) containing exactly the requested
///   zones. Offsets are exact, `is_dst` is inferred heuristically (any offset
///   larger than the zone's minimum is treated as DST), `designation` comes
///   from `Intl`, and leap seconds are ignored (`Temporal` does not model
///   them). Unknown or unbuildable zones are silently skipped.
///
/// Returns `Error(Nil)` on Erlang if no OS database could be read, and on
/// JavaScript if none of the requested zones could be built (for example when
/// `Temporal` is unavailable).
///
/// ## Example
///
/// ```gleam
/// import gleam/time/timestamp
/// import gtz
/// import tzif/tzcalendar
///
/// let assert Ok(db) = gtz.load(["America/New_York"])
/// let ts = timestamp.from_unix_seconds(1_758_223_300)
/// tzcalendar.to_time_and_zone(ts, "America/New_York", db)
/// // -> Ok(TimeAndZone(Date(2025, September, 18), TimeOfDay(15, 21, 40, 0),
/// //      Duration(-14_400, 0), "EDT", True))
/// ```
fn load(zone_names: List(String)) -> Result(TzDatabase, Nil) {
  case is_javascript() {
    True -> load_from_platform(zone_names)
    False -> os_database()
  }
}

/// Convenience wrapper for loading a single zone. See `load`.
fn load_zone(zone_name: String) -> Result(TzDatabase, Nil) {
  load([zone_name])
}

fn load_from_platform(zone_names: List(String)) -> Result(TzDatabase, Nil) {
  let db =
    list.fold(zone_names, database.new(), fn(db, name) {
      case platform_zone_data(name) {
        Ok(rows) -> database.add_tzfile(db, name, build_tzfile(rows))
        Error(_) -> db
      }
    })

  // Signal failure if nothing at all could be built.
  case database.get_available_timezones(db) {
    [] -> Error(Nil)
    _ -> Ok(db)
  }
}

// Each row is #(transition_start_unix_seconds, utc_offset_seconds, designation)
// as reported by the host platform for one offset transition.
type Row =
  #(Int, Int, String)

fn build_tzfile(rows: List(Row)) -> parser.TzFile {
  // Heuristic: standard time is the smallest offset observed for the zone; any
  // larger offset is treated as daylight saving time. This holds for the usual
  // "standard / standard + 1h" arrangement.
  let standard =
    rows
    |> list.map(fn(r) { r.1 })
    |> list.reduce(int_min)
    |> unwrap_or(0)

  let ttinfos =
    list.map(rows, fn(r) {
      let isdst = case r.1 > standard {
        True -> 1
        False -> 0
      }
      // desigidx is unused by the query path because designations are supplied
      // as a parallel list here, so 0 is fine.
      parser.TtInfo(utoff: r.1, isdst: isdst, desigidx: 0)
    })

  let fields =
    parser.TzFileFields(
      transition_times: list.map(rows, fn(r) { r.0 }),
      // time_types[i] = i, indexing 1:1 into ttinfos / designations.
      time_types: list.index_map(rows, fn(_, i) { i }),
      ttinfos:,
      designations: list.map(rows, fn(r) { r.2 }),
      leapsecond_values: [],
      standard_or_wall: [],
      ut_or_local: [],
    )

  let n = list.length(rows)
  parser.TzFile(
    header: parser.TzFileHeader(
      version: 2,
      ttisutcnt: 0,
      ttisstdcnt: 0,
      leapcnt: 0,
      timecnt: n,
      typecnt: n,
      charcnt: 0,
    ),
    fields:,
    remains: <<>>,
  )
}

fn int_min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

fn unwrap_or(r: Result(a, e), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

// True on the JavaScript target (via FFI); the Gleam body below is the Erlang
// fallback and always returns False.
@external(javascript, "./gtz_ffi.mjs", "is_javascript")
fn is_javascript() -> Bool {
  False
}

// Raw native transition facts for one IANA zone. External on JavaScript; the
// Gleam body is the Erlang fallback and is never reached on that target because
// `load` branches to `load_from_os` there.
@external(javascript, "./gtz_ffi.mjs", "zone_transitions")
fn platform_zone_data(_zone_name: String) -> Result(List(Row), Nil) {
  Error(Nil)
}
