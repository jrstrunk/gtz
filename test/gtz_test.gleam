import gleam/float
import gleam/int
import gleam/list
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

fn zone(name: String) -> gtz.TimeZone {
  let assert Ok(zone) = gtz.build(name)
  zone
}

/// The date, time of day, and offset `name` reports for a Unix timestamp.
fn at(name: String, seconds: Int) {
  timestamp.from_unix_seconds(seconds) |> gtz.to_calendar(zone(name))
}

pub fn build_valid_zone_test() {
  let assert Ok(_) = gtz.build("America/New_York")
  let assert Ok(_) = gtz.build("Europe/London")
  let assert Ok(_) = gtz.build("UTC")
}

pub fn build_invalid_zone_test() {
  assert Error(Nil) == gtz.build("America/NewYork")
  assert Error(Nil) == gtz.build("")
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

/// Whatever the host calls itself has to be a zone this package can build.
pub fn local_name_is_buildable_test() {
  let assert Ok(_) = gtz.build(gtz.local_name())
}

// --- Offsets that are not a whole number of hours --------------------------

pub fn to_calendar_half_hour_offset_test() {
  let #(date, time, offset) = at("Asia/Kolkata", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(18, 52, 56, 0)
  assert offset == duration.seconds(19_800)
}

pub fn to_calendar_quarter_hour_offset_test() {
  let #(date, time, offset) = at("Asia/Kathmandu", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(19, 7, 56, 0)
  assert offset == duration.seconds(20_700)
}

pub fn to_calendar_negative_half_hour_offset_test() {
  let #(date, time, offset) = at("America/St_Johns", 1_704_260_202)

  assert date == calendar.Date(2024, calendar.January, 3)
  assert time == calendar.TimeOfDay(2, 6, 42, 0)
  assert offset == duration.seconds(-12_600)
}

/// +12:45 in winter, +13:45 on daylight saving time, which this instant is.
pub fn to_calendar_quarter_hour_daylight_offset_test() {
  let #(date, time, offset) = at("Pacific/Chatham", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 19)
  assert time == calendar.TimeOfDay(3, 7, 56, 0)
  assert offset == duration.seconds(49_500)
}

// --- Zones that are not America/New_York shaped -----------------------------

/// The southern hemisphere is on daylight saving time in January.
pub fn to_calendar_southern_daylight_time_test() {
  let #(date, time, offset) = at("Australia/Sydney", 1_704_260_202)

  assert date == calendar.Date(2024, calendar.January, 3)
  assert time == calendar.TimeOfDay(16, 36, 42, 0)
  assert offset == duration.seconds(39_600)
}

pub fn to_calendar_zone_without_daylight_saving_test() {
  let #(date, time, offset) = at("Asia/Tokyo", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(22, 22, 56, 0)
  assert offset == duration.seconds(32_400)
}

/// Arizona keeps standard time all year while the rest of Mountain time
/// changes around it.
pub fn to_calendar_zone_that_opted_out_test() {
  let #(date, time, offset) = at("America/Phoenix", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(6, 22, 56, 0)
  assert offset == duration.seconds(-25_200)
}

/// Turkey abandoned daylight saving in 2016 and has been on +03 since.
pub fn to_calendar_zone_that_abolished_daylight_saving_test() {
  let #(date, time, offset) = at("Europe/Istanbul", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(16, 22, 56, 0)
  assert offset == duration.seconds(10_800)
}

/// The sign convention here is inverted by design: `Etc/GMT+5` is -05:00.
pub fn to_calendar_fixed_offset_zone_test() {
  let #(date, time, offset) = at("Etc/GMT+5", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(8, 22, 56, 0)
  assert offset == duration.seconds(-18_000)
}

pub fn to_calendar_utc_test() {
  let #(date, time, offset) = at("UTC", 1_729_257_776)

  assert date == calendar.Date(2024, calendar.October, 18)
  assert time == calendar.TimeOfDay(13, 22, 56, 0)
  assert offset == duration.seconds(0)
}

/// The extremes of the inhabited range: +14:00 and -10:00 are a whole calendar
/// day apart at the same instant.
pub fn to_calendar_extreme_offsets_test() {
  let new_year = 1_735_689_600

  let #(date, time, offset) = at("Pacific/Kiritimati", new_year)
  assert date == calendar.Date(2025, calendar.January, 1)
  assert time == calendar.TimeOfDay(14, 0, 0, 0)
  assert offset == duration.seconds(50_400)

  let #(date, time, offset) = at("Pacific/Honolulu", new_year)
  assert date == calendar.Date(2024, calendar.December, 31)
  assert time == calendar.TimeOfDay(14, 0, 0, 0)
  assert offset == duration.seconds(-36_000)
}

pub fn to_calendar_leap_day_test() {
  let #(date, time, _) = at("America/New_York", 1_709_208_000)

  assert date == calendar.Date(2024, calendar.February, 29)
  assert time == calendar.TimeOfDay(7, 0, 0, 0)
}

// --- The instant a transition takes effect ----------------------------------

/// Clocks go back at 06:00 UTC on 2024-11-03. The last second before it still
/// belongs to the old offset, and a minute after it the new one is in effect;
/// both spell 01:xx local, an hour apart in UTC.
///
/// A minute rather than a second after, because the two targets do not agree
/// on the first few seconds: the `zones` fallback ships leap second aware data
/// whose transitions sit 27 seconds later than the same transitions computed
/// from `Intl`. See `to_calendar_near_a_transition_test`.
pub fn to_calendar_at_fall_back_instant_test() {
  let #(date, time, offset) = at("America/New_York", 1_730_613_660)
  assert date == calendar.Date(2024, calendar.November, 3)
  assert time == calendar.TimeOfDay(1, 1, 0, 0)
  assert offset == duration.seconds(-18_000)

  let #(date, time, offset) = at("America/New_York", 1_730_613_599)
  assert date == calendar.Date(2024, calendar.November, 3)
  assert time == calendar.TimeOfDay(1, 59, 59, 0)
  assert offset == duration.seconds(-14_400)
}

/// Clocks go forward at 07:00 UTC on 2024-03-10: local time steps straight
/// from 01:59:59 to 03:00:00.
pub fn to_calendar_at_spring_forward_instant_test() {
  let #(date, time, offset) = at("America/New_York", 1_710_054_060)
  assert date == calendar.Date(2024, calendar.March, 10)
  assert time == calendar.TimeOfDay(3, 1, 0, 0)
  assert offset == duration.seconds(-14_400)

  let #(date, time, offset) = at("America/New_York", 1_710_053_999)
  assert date == calendar.Date(2024, calendar.March, 10)
  assert time == calendar.TimeOfDay(1, 59, 59, 0)
  assert offset == duration.seconds(-18_000)
}

/// Whatever a target's data says the exact transition second is, an offset
/// change is the only thing that may happen across one: a minute either side
/// of a transition the offsets must differ by exactly the shift, and nothing
/// between them may sit outside those two values.
pub fn to_calendar_near_a_transition_test() {
  let zone = new_york()
  let offset_at = fn(seconds) {
    let #(_, _, offset) =
      gtz.to_calendar(timestamp.from_unix_seconds(seconds), zone)
    float.round(duration.to_seconds(offset))
  }

  use transition <- list.each([1_710_054_000, 1_730_613_600])
  assert offset_at(transition - 60) != offset_at(transition + 60)

  use step <- list.each([-60, -27, -1, 0, 1, 27, 60])
  let offset = offset_at(transition + step)
  assert offset == -18_000 || offset == -14_400
}

// --- Ambiguous and impossible wall clock times ------------------------------

/// Sydney's clocks go back at 03:00 on 2025-04-06, so 02:30 happens twice.
pub fn from_calendar_southern_ambiguous_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.April, 6),
      calendar.TimeOfDay(2, 30, 0, 0),
      zone("Australia/Sydney"),
    )

  assert ts == timestamp.from_unix_seconds(1_743_867_000)
}

/// Sydney's clocks jump 02:00 to 03:00 on 2025-10-05.
pub fn from_calendar_southern_skipped_test() {
  let assert Error(Nil) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.October, 5),
      calendar.TimeOfDay(2, 30, 0, 0),
      zone("Australia/Sydney"),
    )
}

/// Lord Howe Island shifts by thirty minutes rather than an hour, so only
/// 01:30 to 01:59 repeats on 2025-04-06.
pub fn from_calendar_half_hour_shift_ambiguous_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.April, 6),
      calendar.TimeOfDay(1, 45, 0, 0),
      zone("Australia/Lord_Howe"),
    )

  assert ts == timestamp.from_unix_seconds(1_743_864_300)
}

/// The other side of the same thirty minute shift: on 2025-10-05 local time
/// goes from 01:59:59 to 02:30:00, so 02:15 never happens.
pub fn from_calendar_half_hour_shift_skipped_test() {
  let assert Error(Nil) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.October, 5),
      calendar.TimeOfDay(2, 15, 0, 0),
      zone("Australia/Lord_Howe"),
    )
}

/// Newfoundland repeats 01:00 to 01:59 on 2025-11-02, at -02:30 then -03:30.
pub fn from_calendar_ambiguous_on_half_hour_zone_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.November, 2),
      calendar.TimeOfDay(1, 30, 0, 0),
      zone("America/St_Johns"),
    )

  assert ts == timestamp.from_unix_seconds(1_762_056_000)
}

/// A zone that never shifts can never be ambiguous.
pub fn from_calendar_in_zone_without_daylight_saving_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.June, 15),
      calendar.TimeOfDay(12, 0, 0, 0),
      zone("Asia/Kolkata"),
    )

  assert ts == timestamp.from_unix_seconds(1_749_969_000)
}

pub fn from_calendar_at_extreme_offset_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2025, calendar.June, 15),
      calendar.TimeOfDay(12, 0, 0, 0),
      zone("Pacific/Kiritimati"),
    )

  assert ts == timestamp.from_unix_seconds(1_749_938_400)
}

// --- Sub-second precision ---------------------------------------------------

pub fn to_calendar_keeps_nanoseconds_test() {
  let #(_, time, _) =
    timestamp.from_unix_seconds_and_nanoseconds(1_729_257_776, 123_456_789)
    |> gtz.to_calendar(new_york())

  assert time == calendar.TimeOfDay(9, 22, 56, 123_456_789)
}

pub fn from_calendar_keeps_nanoseconds_test() {
  let assert Ok(ts) =
    gtz.from_calendar(
      calendar.Date(2024, calendar.October, 18),
      calendar.TimeOfDay(9, 22, 56, 123_456_789),
      new_york(),
    )

  assert ts
    == timestamp.from_unix_seconds_and_nanoseconds(1_729_257_776, 123_456_789)
}

// --- The edges of the range -------------------------------------------------

pub fn to_calendar_at_the_epoch_test() {
  let #(date, time, offset) = at("America/New_York", 0)

  assert date == calendar.Date(1969, calendar.December, 31)
  assert time == calendar.TimeOfDay(19, 0, 0, 0)
  assert offset == duration.seconds(-18_000)
}

/// Before the JavaScript target's window, a zone resolves to its earliest
/// known offset. Kolkata has been +05:30 since well before 1970, so the two
/// targets agree on this instant even though they get there differently.
pub fn to_calendar_before_the_epoch_test() {
  let #(date, time, offset) = at("Asia/Kolkata", -100_000)

  assert date == calendar.Date(1969, calendar.December, 31)
  assert time == calendar.TimeOfDay(1, 43, 20, 0)
  assert offset == duration.seconds(19_800)
}

/// The far end of the window. December is standard time under every rule the
/// zone has ever had, so this holds whether the answer comes from a real
/// transition or from the last one on file.
pub fn to_calendar_far_future_test() {
  let #(date, time, offset) = at("America/New_York", 4_102_444_800)

  assert date == calendar.Date(2099, calendar.December, 31)
  assert time == calendar.TimeOfDay(19, 0, 0, 0)
  assert offset == duration.seconds(-18_000)
}

// --- Building -------------------------------------------------------------

pub fn build_rejects_malformed_names_test() {
  let assert Error(Nil) = gtz.build("Mars/Phobos")
  let assert Error(Nil) = gtz.build("America/New_York/Manhattan")
  let assert Error(Nil) = gtz.build("   ")
  let assert Error(Nil) = gtz.build("America\\New_York")
}

/// Zones are derived once and reused on the JavaScript target, so a second
/// build has to answer exactly as the first did.
pub fn build_is_repeatable_test() {
  let ts = timestamp.from_unix_seconds(1_729_257_776)
  let assert Ok(first) = gtz.build("Europe/Paris")
  let assert Ok(second) = gtz.build("Europe/Paris")

  assert gtz.to_calendar(ts, first) == gtz.to_calendar(ts, second)
}

// --- Properties over a whole year ------------------------------------------

/// Every hour of 2024, as Unix seconds. It is a leap year, so 8784 of them.
fn hours_of_2024() -> List(Int) {
  use acc, hour <- int.range(from: 0, to: 8784, with: [])
  [1_704_067_200 + hour * 3600, ..acc]
}

/// The date and time a zone reports, read back at the offset it reported
/// alongside them, has to land on the instant that was asked about. A slice
/// picked one transition early or late fails this everywhere it applies.
pub fn to_calendar_agrees_with_its_own_offset_test() {
  let zone = new_york()

  use seconds <- list.each(hours_of_2024())
  let ts = timestamp.from_unix_seconds(seconds)
  let #(date, time, offset) = gtz.to_calendar(ts, zone)

  assert timestamp.from_calendar(date, time, offset) == ts
}

/// In a zone that never shifts, no wall clock time is ambiguous or skipped, so
/// the round trip is exact for every hour of the year.
pub fn round_trip_is_exact_without_daylight_saving_test() {
  let zone = zone("Asia/Kolkata")

  use seconds <- list.each(hours_of_2024())
  let ts = timestamp.from_unix_seconds(seconds)
  let #(date, time, _) = gtz.to_calendar(ts, zone)

  assert gtz.from_calendar(date, time, zone) == Ok(ts)
}

/// Over 2024 New York uses exactly two offsets, an hour apart, and Kolkata
/// exactly one. This is what says the transition list is neither missing
/// changes nor inventing them.
pub fn offsets_used_over_a_year_test() {
  // Offsets are compared as whole seconds rather than with `duration.compare`,
  // which ranks durations by the amount of time they span. A UTC offset is a
  // signed position rather than a span, so -04:00 has to sort after -05:00
  // even though it is the shorter of the two.
  let offsets = fn(zone) {
    hours_of_2024()
    |> list.map(fn(seconds) {
      let #(_, _, offset) =
        gtz.to_calendar(timestamp.from_unix_seconds(seconds), zone)
      float.round(duration.to_seconds(offset))
    })
    |> list.unique
    |> list.sort(int.compare)
  }

  assert offsets(new_york()) == [-18_000, -14_400]
  assert offsets(zone("Asia/Kolkata")) == [19_800]
}

// --- Zones that break the usual rules ---------------------------------------

/// Brazil abolished daylight saving after the 2018-19 summer, so January is
/// -02:00 in 2019 and -03:00 in 2020.
pub fn to_calendar_zone_that_stopped_shifting_test() {
  let #(_, time, offset) = at("America/Sao_Paulo", 1_547_553_600)
  assert time == calendar.TimeOfDay(10, 0, 0, 0)
  assert offset == duration.seconds(-7200)

  let #(_, time, offset) = at("America/Sao_Paulo", 1_579_089_600)
  assert time == calendar.TimeOfDay(9, 0, 0, 0)
  assert offset == duration.seconds(-10_800)
}

/// Iran dropped daylight saving in 2022. +04:30 in the summer before, +03:30
/// in the summer after.
pub fn to_calendar_zone_that_stopped_shifting_on_a_half_hour_test() {
  let #(_, time, offset) = at("Asia/Tehran", 1_623_758_400)
  assert time == calendar.TimeOfDay(16, 30, 0, 0)
  assert offset == duration.seconds(16_200)

  let #(_, time, offset) = at("Asia/Tehran", 1_686_830_400)
  assert time == calendar.TimeOfDay(15, 30, 0, 0)
  assert offset == duration.seconds(12_600)
}

/// The tz database models Ireland as being on negative daylight saving in
/// winter rather than positive in summer. The offsets are the same either way,
/// which is the whole reason nothing here reasons about which is which.
pub fn to_calendar_zone_with_negative_daylight_saving_test() {
  let #(_, _, offset) = at("Europe/Dublin", 1_705_320_000)
  assert offset == duration.seconds(0)

  let #(_, _, offset) = at("Europe/Dublin", 1_721_044_800)
  assert offset == duration.seconds(3600)
}

/// Troll station shifts by two hours, not one.
pub fn to_calendar_two_hour_shift_test() {
  let #(_, time, offset) = at("Antarctica/Troll", 1_705_320_000)
  assert time == calendar.TimeOfDay(12, 0, 0, 0)
  assert offset == duration.seconds(0)

  let #(_, time, offset) = at("Antarctica/Troll", 1_721_044_800)
  assert time == calendar.TimeOfDay(14, 0, 0, 0)
  assert offset == duration.seconds(7200)
}

/// Morocco is on +01:00 but drops to +00:00 for Ramadan, so it shifts four
/// times a year rather than twice, and one of those periods is about a month
/// long. Finding all three of these means the transition search is not
/// stepping over short periods.
pub fn to_calendar_zone_with_a_ramadan_pause_test() {
  let #(_, _, offset) = at("Africa/Casablanca", 1_705_320_000)
  assert offset == duration.seconds(3600)

  let #(_, time, offset) = at("Africa/Casablanca", 1_710_936_000)
  assert time == calendar.TimeOfDay(12, 0, 0, 0)
  assert offset == duration.seconds(0)

  let #(_, _, offset) = at("Africa/Casablanca", 1_715_774_400)
  assert offset == duration.seconds(3600)
}

// --- Days that never happened -----------------------------------------------

/// Samoa crossed the international date line at the end of 2011, going from
/// 23:59:59 on the 29th of December straight to 00:00:00 on the 31st.
pub fn to_calendar_across_a_date_line_jump_test() {
  let #(date, time, offset) = at("Pacific/Apia", 1_325_239_199)
  assert date == calendar.Date(2011, calendar.December, 29)
  assert time == calendar.TimeOfDay(23, 59, 59, 0)
  assert offset == duration.seconds(-36_000)

  // A minute after the jump rather than the instant of it, to clear the 27
  // second disagreement between the two targets described on
  // `to_calendar_at_fall_back_instant_test`.
  let #(date, time, offset) = at("Pacific/Apia", 1_325_239_260)
  assert date == calendar.Date(2011, calendar.December, 31)
  assert time == calendar.TimeOfDay(0, 1, 0, 0)
  assert offset == duration.seconds(50_400)
}

pub fn from_calendar_on_a_skipped_day_test() {
  let assert Error(Nil) =
    gtz.from_calendar(
      calendar.Date(2011, calendar.December, 30),
      calendar.TimeOfDay(12, 0, 0, 0),
      zone("Pacific/Apia"),
    )

  // Kiritimati made the same crossing in 1994, skipping the 31st of December
  let assert Error(Nil) =
    gtz.from_calendar(
      calendar.Date(1994, calendar.December, 31),
      calendar.TimeOfDay(12, 0, 0, 0),
      zone("Pacific/Kiritimati"),
    )
}

/// The days either side of a skipped one still resolve normally.
pub fn from_calendar_around_a_skipped_day_test() {
  let apia = zone("Pacific/Apia")

  let assert Ok(before) =
    gtz.from_calendar(
      calendar.Date(2011, calendar.December, 29),
      calendar.TimeOfDay(23, 0, 0, 0),
      apia,
    )
  assert before == timestamp.from_unix_seconds(1_325_235_600)

  let assert Ok(after) =
    gtz.from_calendar(
      calendar.Date(2011, calendar.December, 31),
      calendar.TimeOfDay(0, 30, 0, 0),
      apia,
    )
  assert after == timestamp.from_unix_seconds(1_325_241_000)
}

// --- Link names -------------------------------------------------------------

/// Deprecated names are links to a canonical zone and have to answer the same.
pub fn link_names_agree_with_canonical_zones_test() {
  let ts = timestamp.from_unix_seconds(1_705_320_000)
  let same = fn(link, canonical) {
    assert gtz.to_calendar(ts, zone(link))
      == gtz.to_calendar(ts, zone(canonical))
  }

  same("US/Eastern", "America/New_York")
  same("Asia/Calcutta", "Asia/Kolkata")
  same("Etc/UTC", "UTC")
  same("GMT", "UTC")
}

// --- The exact edges of an ambiguous or skipped range -----------------------

/// New York loses 02:00 to 02:59 on 2025-03-09. Times either side of the lost
/// hour resolve; every minute inside it is gone.
///
/// The minutes sampled stay clear of 02:00 and 03:00 exactly, because the two
/// targets put the edges of the range 27 seconds apart. See
/// `to_calendar_at_fall_back_instant_test`.
pub fn from_calendar_edges_of_a_skipped_range_test() {
  let at_time = fn(hour, minute) {
    gtz.from_calendar(
      calendar.Date(2025, calendar.March, 9),
      calendar.TimeOfDay(hour, minute, 0, 0),
      new_york(),
    )
  }

  assert at_time(1, 58) == Ok(timestamp.from_unix_seconds(1_741_503_480))
  assert at_time(2, 1) == Error(Nil)
  assert at_time(2, 30) == Error(Nil)
  assert at_time(2, 59) == Error(Nil)
  assert at_time(3, 1) == Ok(timestamp.from_unix_seconds(1_741_503_660))
}

/// New York repeats 01:00 to 01:59 on 2025-11-02. Inside the range the earlier
/// instant is returned; outside it there is only ever one.
pub fn from_calendar_edges_of_an_ambiguous_range_test() {
  let at_time = fn(hour, minute) {
    gtz.from_calendar(
      calendar.Date(2025, calendar.November, 2),
      calendar.TimeOfDay(hour, minute, 0, 0),
      new_york(),
    )
  }

  assert at_time(0, 59) == Ok(timestamp.from_unix_seconds(1_762_059_540))
  assert at_time(1, 0) == Ok(timestamp.from_unix_seconds(1_762_059_600))
  assert at_time(1, 59) == Ok(timestamp.from_unix_seconds(1_762_063_140))
  // 02:01 rather than 02:00, which is the disputed second itself
  assert at_time(2, 1) == Ok(timestamp.from_unix_seconds(1_762_066_860))
}

/// An ambiguous wall clock time has to come back as the same wall clock time,
/// whichever of the two instants is picked. This is what says the earlier one
/// is a real occurrence of it rather than an hour adrift.
pub fn ambiguous_times_round_trip_to_themselves_test() {
  let zone = new_york()
  let date = calendar.Date(2025, calendar.November, 2)

  use minute <- list.each([0, 1, 30, 58, 59])
  let time = calendar.TimeOfDay(1, minute, 0, 0)
  let assert Ok(ts) = gtz.from_calendar(date, time, zone)
  let #(round_tripped_date, round_tripped_time, _) = gtz.to_calendar(ts, zone)

  assert round_tripped_date == date
  assert round_tripped_time == time
}

// --- Sub-second edges -------------------------------------------------------

pub fn nanosecond_extremes_round_trip_test() {
  let zone = zone("Australia/Adelaide")

  use nanoseconds <- list.each([0, 1, 500_000_000, 999_999_999])
  let ts =
    timestamp.from_unix_seconds_and_nanoseconds(1_729_257_776, nanoseconds)
  let #(date, time, _) = gtz.to_calendar(ts, zone)

  assert time.nanoseconds == nanoseconds
  assert gtz.from_calendar(date, time, zone) == Ok(ts)
}

// --- Invariants that must hold for every zone -------------------------------

/// A spread of zones covering whole, half and quarter hour offsets, both
/// hemispheres, fixed offsets, links, and zones that have crossed the date
/// line or changed their rules.
const sample_zones =
  [
    "UTC", "America/New_York", "America/Sao_Paulo", "America/St_Johns",
    "Europe/London", "Europe/Dublin", "Europe/Istanbul", "Africa/Casablanca",
    "Asia/Kolkata", "Asia/Kathmandu", "Asia/Tokyo", "Asia/Tehran",
    "Australia/Adelaide", "Australia/Lord_Howe", "Pacific/Chatham",
    "Pacific/Apia", "Pacific/Kiritimati", "Antarctica/Troll", "Etc/GMT+5",
    "US/Eastern",
  ]

pub fn every_sample_zone_builds_test() {
  use name <- list.each(sample_zones)
  let assert Ok(_) = gtz.build(name)
}

/// Noon UTC on every day of 2024, as Unix seconds.
fn days_of_2024() -> List(Int) {
  use acc, day <- int.range(from: 0, to: 366, with: [])
  [1_704_110_400 + day * 86_400, ..acc]
}

/// No zone has used an offset outside ±14 hours, or one that is not a whole
/// quarter of an hour, at any point in the modern era. An offset that fails
/// either check is a misread record rather than a real zone.
pub fn offsets_are_plausible_test() {
  use name <- list.each(sample_zones)
  let zone = zone(name)

  use seconds <- list.each(days_of_2024())
  let #(_, _, offset) =
    gtz.to_calendar(timestamp.from_unix_seconds(seconds), zone)
  let offset = float.round(duration.to_seconds(offset))

  assert offset >= -50_400 && offset <= 50_400
  assert offset % 900 == 0
}

/// The self consistency check that `to_calendar_agrees_with_its_own_offset`
/// makes for New York, made for every sample zone across a year. This is the
/// broadest statement that the module can be trusted: whatever slice a zone
/// picks, reading it back has to land on the instant that was asked about.
pub fn to_calendar_agrees_with_its_own_offset_everywhere_test() {
  use name <- list.each(sample_zones)
  let zone = zone(name)

  use seconds <- list.each(days_of_2024())
  let ts = timestamp.from_unix_seconds(seconds)
  let #(date, time, offset) = gtz.to_calendar(ts, zone)

  assert timestamp.from_calendar(date, time, offset) == ts
}

/// Noon never falls in a skipped hour, so every sample zone must be able to
/// convert it back, and back to the instant it came from.
pub fn round_trip_at_noon_everywhere_test() {
  use name <- list.each(sample_zones)
  let zone = zone(name)

  use seconds <- list.each(days_of_2024())
  let ts = timestamp.from_unix_seconds(seconds)
  let #(date, time, _) = gtz.to_calendar(ts, zone)

  assert gtz.from_calendar(date, time, zone) == Ok(ts)
}
