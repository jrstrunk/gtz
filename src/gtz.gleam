//// Functions to provide simple timezone support for other Gleam datetime libraries.

import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import tempo
import tempo/naive_datetime
import tempo/offset

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

@external(erlang, "Elixir.GTZ_FFI", "calculate_offset")
@external(javascript, "./gtz_ffi.mjs", "calculate_offset")
fn calculate_offset_ffi(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
  timezone: String,
) -> Int

@external(erlang, "Elixir.GTZ_FFI", "is_valid_timezone")
@external(javascript, "./gtz_ffi.mjs", "is_valid_timezone")
fn is_valid_timezone(timezone: String) -> Bool

/// Returns the name of the host system's timezone.
///
/// ## Examples
///
/// ```gleam
/// gtz.local_name()
/// // -> "Europe/London"
/// ```
@external(erlang, "Elixir.Timex.Timezone.Local", "lookup")
@external(javascript, "./gtz_ffi.mjs", "local_timezone")
pub fn local_name() -> String
