//// Simple Gleam time zone conversions for all targets, built on top of `tzif`.
////
//// Converting an ambiguous calendar time to a timestamp
//// assumes the first occurrence of the ambiguous time. Accounting for leap
//// seconds depends on the dataset. If you need more control over how
//// ambiguous dates are handled or the designation of the given time in the
//// zone, use the `tzif` package directly.
////
//// The `build` function reads the host's own time zone data. When the host
//// has none, or when it is somewhere other than where the host usually stores
//// it, supply a database yourself with `build_from` using the very nice
//// `tzif` or `zones` packages. If you are running this in a bare environment
//// with no time zone data available, the `zones` package is recommended.
////
//// ```gleam
//// import gleam/time/timestamp
//// import gtz
////
//// let zone_name = gtz.local_name() // "Asia/Kolkata"
//// let assert Ok(zone) = gtz.build(zone_name)
////
//// timestamp.from_unix_seconds(1_729_257_776)
//// |> gtz.to_calendar(zone)
//// // -> #(
//// //   calendar.Date(2024, calendar.October, 18),
//// //   calendar.TimeOfDay(18, 52, 56, 0),
//// //   duration.seconds(19_800),
//// // )
//// ```

import gleam/list
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import tzif/database
import tzif/parser
import tzif/tzcalendar

/// Data for an IANA time zone. Build with `build`, then hand to `to_calendar` or
/// `from_calendar`.
///
/// ## Examples
///
/// ```gleam
/// gtz.build("Asia/Kolkata")
/// // -> Ok(TimeZone)
/// ```
pub opaque type TimeZone {
  TimeZone(name: String, database: database.TzDatabase)
}

/// Build a `TimeZone` from an IANA zone name such as `"America/New_York"`.
/// Returns an error if the name is not a zone the host recognizes.
///
/// On the Erlang target, the operating system's TZif database at
/// `/usr/share/zoneinfo` is read once and memoized into a persistent term. A
/// host with no zoneinfo tree there, such as a scratch container image, has no
/// zone to recognize and every name fails; use `build_from` and provide your own
/// database from the very nice `tzif` or `zones` packages instead. On
/// JavaScript, information for the given zone is derived from the host's
/// native `Temporal` and `Intl` APIs.
///
/// ## Examples
///
/// ```gleam
/// gtz.local_name() |> gtz.build
/// // -> Ok(TimeZone)
///
/// gtz.build("Asia/Kolkata")
/// // -> Ok(TimeZone)
///
/// gtz.build("America/NewYork") // "New_York" is the correct name here
/// // -> Error(Nil)
/// ```
pub fn build(name: String) -> Result(TimeZone, Nil) {
  use db <- result.try(database_for(name))
  resolve(name, db)
}

/// Build a `TimeZone` from an IANA zone name and a `tzif` database of your own.
/// Returns an error if the database holds no usable data for the name.
///
/// Use this when working in a bare environment (such as a scratch container
/// image on the Erlang target), a host that keeps its zoneinfo somewhere
/// other than `/usr/share/zoneinfo`, or you need precise control over the
/// dataset.
///
/// The `zones` package ships a prebuilt database and needs no files at all,
/// which suits bare environments. `tzif` itself can load from any directory,
/// which suits a non-standard location or a database you compiled yourself.
///
/// ## Examples
///
/// ```gleam
/// import zones
///
/// let assert Ok(zone) = gtz.build_from("Asia/Kolkata", zones.database())
/// // -> Ok(TimeZone)
/// ```
///
/// ```gleam
/// import tzif/database
///
/// let assert Ok(db) = database.load_from_path("/opt/zoneinfo")
/// let assert Ok(zone) = gtz.build_from("Asia/Kolkata", db)
/// // -> Ok(TimeZone)
/// ```
pub fn build_from(
  name: String,
  database db: database.TzDatabase,
) -> Result(TimeZone, Nil) {
  resolve(name, db)
}

/// Check that a name resolves in a database, and pair the two if it does.
fn resolve(name: String, db: database.TzDatabase) -> Result(TimeZone, Nil) {
  // Resolving the zone once here is what makes `to_calendar` infallable. `tzif`
  // fails a lookup when the name is absent, or when the zone's file carries no
  // offset records at all; neither depends on which timestamp was asked for,
  // so a zone that resolves at the epoch resolves at every other instant too.
  // Nothing can invalidate that afterwards, as `TimeZone` is opaque and the
  // database it holds is immutable.
  use _ <- result.map(
    database.get_zone_parameters(timestamp.from_unix_seconds(0), name, db)
    |> result.replace_error(Nil),
  )

  TimeZone(name:, database: db)
}

/// Convert a timestamp to the equivalent date, time of day, and UTC offset
/// in the given time zone.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(zone) = gtz.build("Asia/Kathmandu")
///
/// // Not every zone is a whole number of hours from UTC
/// timestamp.from_unix_seconds(1_729_257_776)
/// |> gtz.to_calendar(zone)
/// // -> #(
/// //   calendar.Date(2024, calendar.October, 18),
/// //   calendar.TimeOfDay(19, 7, 56, 0),
/// //   duration.seconds(20_700),
/// // )
/// ```
pub fn to_calendar(
  timestamp: timestamp.Timestamp,
  zone: TimeZone,
) -> #(calendar.Date, calendar.TimeOfDay, duration.Duration) {
  let assert Ok(found) =
    tzcalendar.to_time_and_zone(timestamp, zone.name, zone.database)
    as "a TimeZone can only exist for a zone that resolves at every instant"

  #(found.date, found.time_of_day, found.offset)
}

/// Convert a date and time of day in `zone` to a timestamp. When you know
/// the offset, always prefer the `timestamp.from_calendar` in `gleam_time`
/// over this function.
///
/// When the time is ambiguous in the given time zone because of an offset
/// change such as daylight saving time, the timestamp that corresponds with
/// the first occurrence of that time is returned. When the time does not exist
/// in the given time zone because of an offset change such as daylight saving
/// time, `Error(Nil)` is returned.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(zone) = gtz.build("Australia/Lord_Howe")
///
/// // Clocks go back half an hour at 02:00, so 01:30 to 01:59 happens twice
/// gtz.from_calendar(
///   calendar.Date(2025, calendar.April, 6),
///   calendar.TimeOfDay(1, 45, 0, 0),
///   zone,
/// )
/// // -> Ok(Timestamp(1_743_864_300, 0)), the earlier of the two timestamps
///
/// // Clocks go forward from 02:00 to 02:30, so 02:15 never happens
/// gtz.from_calendar(
///   calendar.Date(2025, calendar.October, 5),
///   calendar.TimeOfDay(2, 15, 0, 0),
///   zone,
/// )
/// // -> Error(Nil)
/// ```
pub fn from_calendar(
  date: calendar.Date,
  time: calendar.TimeOfDay,
  zone: TimeZone,
) -> Result(timestamp.Timestamp, Nil) {
  let assert Ok(candidates) =
    tzcalendar.from_calendar(date, time, zone.name, zone.database)
    as "a TimeZone can only exist for a zone that resolves at every instant"

  // `tzif` returns both sides of an ambiguous wall clock time, and nothing at
  // all for one the clocks skipped over. The earlier timestamp is the first
  // occurrence.
  candidates |> list.sort(timestamp.compare) |> list.first
}

/// Returns the name of the host system's time zone.
///
/// ## Examples
///
/// ```gleam
/// gtz.local_name()
/// // -> "Pacific/Auckland"
/// ```
///
/// On the Erlang target the zone is read from the operating system, in order:
/// the `TZ` environment variable, the symlink target of `/etc/localtime`, then
/// `/etc/timezone` or `/etc/sysconfig/clock`. If none of those yield an IANA
/// zone name, `"UTC"` is returned. On JavaScript the host's `Intl` API is used.
@external(erlang, "gtz_ffi", "local_timezone")
@external(javascript, "./gtz_ffi.mjs", "local_timezone")
pub fn local_name() -> String

/// The database to answer queries about `name` from.
fn database_for(name: String) -> Result(database.TzDatabase, Nil) {
  case platform_zone_data(name) {
    Ok(rows) ->
      Ok(database.add_tzfile(database.new(), name, build_tzfile(rows)))
    Error(_) -> host_database()
  }
}

/// The host's own TZif database, loaded once and memoized.
///
/// The Erlang FFI reads the operating system's zoneinfo tree. There is no
/// fallback: a host without one cannot say what its zones are, and inventing
/// an answer would be worse than `build` failing and the caller reaching for
/// `build_from`.
@external(erlang, "gtz_ffi", "host_database")
fn host_database() -> Result(database.TzDatabase, Nil) {
  Error(Nil)
}

/// Raw native transition facts for one IANA zone, from the host's `Temporal`
/// or `Intl` APIs: `#(start_unix_seconds, utc_offset_seconds)` per slice.
@external(javascript, "./gtz_ffi.mjs", "zone_transitions")
fn platform_zone_data(_zone_name: String) -> Result(List(#(Int, Int)), Nil) {
  Error(Nil)
}

/// Assemble platform transition rows into the TZif shape `tzif` queries.
///
/// `rows` is never empty: both platform implementations emit a baseline row
/// for the start of their window before any transitions. That matters, because
/// a zone with no offset records at all is exactly the one case `tzif` cannot
/// resolve, and `build` rejects it.
fn build_tzfile(rows: List(#(Int, Int))) -> parser.TzFile {
  let ttinfos =
    list.map(rows, fn(row) {
      // Only `utoff` is read back: `gtz` answers with the offset, and every
      // `tzif` query keys off it alone. `isdst` and `desigidx` are inert
      // fields of the record `tzif` wants, so they are pinned at 0 rather
      // than derived. Deriving `isdst` would mean guessing which offsets are
      // daylight saving, and nothing here would ever check the guess.
      parser.TtInfo(utoff: row.1, isdst: 0, desigidx: 0)
    })

  let fields =
    parser.TzFileFields(
      transition_times: list.map(rows, fn(row) { row.0 }),
      // time_types[i] = i, indexing 1:1 into ttinfos / designations.
      time_types: list.index_map(rows, fn(_, i) { i }),
      ttinfos:,
      // Zone abbreviations like "EDT" are never surfaced by `gtz`, so no real
      // ones are gathered. The list still has to run one entry per slice:
      // `tzif` zips it against `ttinfos`, and a short one would silently drop
      // the slices past its end.
      designations: list.map(rows, fn(_) { "" }),
      leapsecond_values: [],
      standard_or_wall: [],
      ut_or_local: [],
    )

  // `tzif` reads `fields` only; the header exists to complete the record it
  // parses files into, and no query consults it. Hence zeroes rather than
  // counts that would have to be kept true.
  parser.TzFile(
    header: parser.TzFileHeader(
      version: 2,
      ttisutcnt: 0,
      ttisstdcnt: 0,
      leapcnt: 0,
      timecnt: 0,
      typecnt: 0,
      charcnt: 0,
    ),
    fields:,
    remains: <<>>,
  )
}
