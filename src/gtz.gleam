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

// True on the JavaScript target (via FFI); the Gleam body below is the Erlang
// fallback and always returns False.
@external(javascript, "./gtz_ffi.mjs", "is_javascript")
fn is_javascript() -> Bool {
  False
}
