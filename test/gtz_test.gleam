import gleeunit
import gleeunit/should
import gtz
import tempo/datetime
import tempo/duration

pub fn main() {
  gleeunit.main()
}

pub fn valid_timezone_test() {
  "America/New_York"
  |> gtz.timezone
  |> should.be_ok
}

pub fn invalid_timezone_test() {
  "America/NewYork"
  |> gtz.timezone
  |> should.be_error
}

pub fn calculate_offset_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-01-03T05:30:02.334Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_string
  |> should.equal("2024-01-03T00:30:02.334-05:00")
}

pub fn calculate_offset_twice_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")
  let assert Ok(tz2) = gtz.timezone("Europe/London")

  datetime.literal("2024-06-03T05:30:02.334Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_timezone(tz2)
  |> datetime.to_string
  |> should.equal("2024-06-03T06:30:02.334+01:00")
}

pub fn calculate_offset_dst_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-07-08T10:30:02.334Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_string
  |> should.equal("2024-07-08T06:30:02.334-04:00")
}

pub fn unix_to_tz_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  1_729_257_776
  |> datetime.from_unix_utc
  |> datetime.to_timezone(tz)
  |> datetime.to_string
  |> should.equal("2024-10-18T09:22:56.000-04:00")
}

pub fn add_to_tz_test() {
  let assert Ok(tz) = gtz.timezone("Europe/London")

  datetime.literal("2024-07-18T09:22:56.542Z")
  |> datetime.to_timezone(tz)
  |> datetime.add(duration.hours(6))
  |> datetime.to_string
  |> should.equal("2024-07-18T16:22:56.542+01:00")
}

pub fn subtract_from_tz_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-07-18T09:22:56.000Z")
  |> datetime.to_timezone(tz)
  |> datetime.subtract(duration.minutes(6))
  |> datetime.subtract(duration.hours(2))
  |> datetime.to_string
  |> should.equal("2024-07-18T03:16:56.000-04:00")
}

pub fn to_tz_before_dst_start_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-03-10T06:32:45.354Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_string
  |> should.equal("2024-03-10T01:32:45.354-05:00")
}

pub fn add_over_dst_start_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-03-10T06:32:45.354Z")
  |> datetime.to_timezone(tz)
  |> datetime.add(duration.hours(1))
  |> datetime.to_string
  |> should.equal("2024-03-10T03:32:45.354-04:00")
}

pub fn to_tz_before_dst_end_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-11-03T05:32:45.354Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_string
  |> should.equal("2024-11-03T01:32:45.354-04:00")
}

pub fn add_over_dst_end_test() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-11-03T05:32:45.354Z")
  |> datetime.to_timezone(tz)
  |> datetime.add(duration.hours(1))
  |> datetime.to_string
  |> should.equal("2024-11-03T01:32:45.354-05:00")
}

pub fn get_tz_name_test() {
  let assert Ok(tz) = gtz.timezone("Europe/London")

  tz.get_name()
  |> should.equal("Europe/London")
}
