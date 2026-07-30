import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import gtz

pub fn main() {
  gleeunit.main()
}

fn new_york() -> gtz.TimeZone {
  let assert Ok(zone) = gtz.build("America/New_York")
  zone
}

pub fn build_valid_zone_test() {
  let assert Ok(_) = gtz.build("America/New_York")
  let assert Ok(_) = gtz.build("Europe/London")
  let assert Ok(_) = gtz.build("UTC")
}

pub fn build_invalid_zone_test() {
  let assert Error(Nil) = gtz.build("America/NewYork")
  let assert Error(Nil) = gtz.build("")
}

pub fn to_calendar_standard_time_test() {
  let #(date, time, offset) =
    timestamp.from_unix_seconds(1_704_260_202)
    |> gtz.to_calendar(new_york())

  assert date == calendar.Date(2024, calendar.January, 3)
  assert time == calendar.TimeOfDay(0, 36, 42, 0)
  assert offset == duration.seconds(-18_000)
}

pub fn to_calendar_daylight_time_test() {
  let #(date, time, offset) =
    timestamp.from_unix_seconds(1_729_257_776)
    |> gtz.to_calendar(new_york())

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(9, 22, 56, 0)
  assert offset == duration.seconds(-14_400)
}

pub fn to_calendar_day_boundary_test() {
  let #(date, time, _) =
    timestamp.from_unix_seconds(1_704_240_000)
    |> gtz.to_calendar(new_york())

  assert date == calendar.Date(2024, calendar.January, 2)
  assert time == calendar.TimeOfDay(19, 0, 0, 0)
}

pub fn to_calendar_other_zone_test() {
  let assert Ok(zone) = gtz.build("Europe/London")

  let #(date, time, offset) =
    timestamp.from_unix_seconds(1_717_392_602)
    |> gtz.to_calendar(zone)

  assert date == calendar.Date(2024, calendar.June, 3)
  assert time == calendar.TimeOfDay(6, 30, 2, 0)
  assert offset == duration.seconds(3600)
}

pub fn round_trip_test() {
  let ts = timestamp.from_unix_seconds(1_729_257_776)
  let zone = new_york()

  let #(date, time, _) = gtz.to_calendar(ts, zone)
  let assert Ok(back) = gtz.from_calendar(date, time, zone)

  assert back == ts
}

pub fn from_calendar_unambiguous_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2024, calendar.July, 8),
      calendar.TimeOfDay(6, 30, 2, 0),
      new_york(),
    )

  assert ts == timestamp.from_unix_seconds(1_720_434_602)
}

/// Clocks go back at 02:00 on 2025-11-02, so 01:30 happens twice: once at
/// -04:00 and again an hour later at -05:00. The earlier one wins.
pub fn from_calendar_ambiguous_takes_first_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.November, 2),
      calendar.TimeOfDay(1, 30, 0, 0),
      new_york(),
    )

  assert ts == timestamp.from_unix_seconds(1_762_061_400)
}

/// Clocks jump from 02:00 to 03:00 on 2025-03-09, so 02:30 never happens.
pub fn from_calendar_skipped_time_test() {
  let assert Error(Nil) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.March, 9),
      calendar.TimeOfDay(2, 30, 0, 0),
      new_york(),
    )
}

pub fn local_name_test() {
  assert gtz.local_name() != ""
  assert !string.contains(gtz.local_name(), ",")
}
