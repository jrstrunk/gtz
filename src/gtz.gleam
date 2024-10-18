//// Functions to provide simple timezone support for other Gleam datetime libraries.

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
              calculate_offset(year, month, day, hour, minute, second, name)
              |> offset.new

            offset
          },
        ),
      )
    False -> Error(Nil)
  }
}

@external(erlang, "Elixir.GTZ_FFI", "calculate_offset")
@external(javascript, "./gtz_ffi.mjs", "calculate_offset")
fn calculate_offset(
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
