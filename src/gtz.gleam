//// Simple, cross target time zone support for `gleam_time`.
////
//// The whole API is one type and three functions: build a `TimeZone` from an
//// IANA zone name, then convert timestamps to and from calendar dates with it.
////
//// ```gleam
//// import gleam/time/timestamp
//// import gtz
////
//// let assert Ok(zone) = gtz.build("America/New_York")
////
//// timestamp.from_unix_seconds(1_729_257_776)
//// |> gtz.to_calendar(zone)
//// // -> #(
//// //   calendar.Date(2024, calendar.October, 18),
//// //   calendar.TimeOfDay(9, 22, 56, 0),
//// //   duration.seconds(-14_400),
//// // )
//// ```
////
//// The conversions themselves are `tzif`'s; what this package adds is getting
//// a usable database in place on both targets without the caller thinking
//// about it. See `build` for where the data comes from.

import gleam/list
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import tzif/database.{type TzDatabase}
import tzif/parser
import tzif/tzcalendar

/// An IANA time zone, paired with the time zone data needed to interpret it.
///
/// Build one with `build`, then hand it to `to_calendar` or `from_calendar`.
pub opaque type TimeZone {
  TimeZone(name: String, database: TzDatabase)
}

/// Build a `TimeZone` from an IANA zone name such as `"America/New_York"`.
/// Returns an error if the name is not a zone this host has usable data for.
///
/// Where the underlying data comes from depends on the target:
///
/// - On **Erlang**, the operating system's TZif database (usually
///   `/usr/share/zoneinfo`) is read once and memoized. If the host has no
///   zoneinfo tree, the prebuilt `zones` database is used instead, so this
///   works on a bare container image too.
/// - On **JavaScript**, where there is no filesystem to read TZif files from,
///   a lean database covering just this one zone is synthesized from the
///   host's native `Temporal` and `Intl` APIs.
///
/// ## Examples
///
/// ```gleam
/// gtz.build("America/New_York")
/// // -> Ok(TimeZone(..))
///
/// gtz.build("America/NewYork")
/// // -> Error(Nil)
/// ```
pub fn build(name: String) -> Result(TimeZone, Nil) {
  use db <- result.try(database_for(name))

  // Resolving the zone once here is what makes `to_calendar` total. `tzif`
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

/// Convert a timestamp to the date, time of day, and UTC offset that a wall
/// clock in `zone` would show for it.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(zone) = gtz.build("America/New_York")
///
/// timestamp.from_unix_seconds(1_729_257_776)
/// |> gtz.to_calendar(zone)
/// // -> #(
/// //   calendar.Date(2024, calendar.October, 18),
/// //   calendar.TimeOfDay(9, 22, 56, 0),
/// //   duration.seconds(-14_400),
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

/// Convert a date and time of day in `zone` back to a timestamp.
///
/// Daylight saving time makes this direction partial. When the wall clock time
/// is ambiguous, because the clocks went back and it happened twice, the first
/// occurrence is returned. When it never existed at all, because the clocks
/// went forward over it, `Error(Nil)` is returned.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(zone) = gtz.build("America/New_York")
///
/// gtz.from_calendar(
///   calendar.Date(2025, calendar.November, 2),
///   calendar.TimeOfDay(1, 30, 0, 0),
///   zone,
/// )
/// // -> Ok(Timestamp(1_762_061_400, 0)), the earlier of the two 01:30s
///
/// gtz.from_calendar(
///   calendar.Date(2025, calendar.March, 9),
///   calendar.TimeOfDay(2, 30, 0, 0),
///   zone,
/// )
/// // -> Error(Nil), that clock time was skipped
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

/// The database to answer queries about `name` from.
///
/// Only one of the two branches is ever live on a given target, because each
/// FFI below is a no-op on the other one. JavaScript has no filesystem to read
/// a whole TZif tree from, so it derives just the requested zone from the
/// host's own time zone engine; Erlang has no `Temporal`, so it reads the tree.
fn database_for(name: String) -> Result(TzDatabase, Nil) {
  case platform_zone_data(name) {
    Ok(rows) ->
      Ok(database.add_tzfile(database.new(), name, build_tzfile(rows)))
    Error(_) -> host_database()
  }
}

/// The host's own TZif database, loaded once and memoized.
///
/// The Erlang FFI prefers the operating system's zoneinfo tree and falls back
/// to the prebuilt `zones` database. That fallback lives in the FFI rather
/// than here so the several megabytes of `zones` are never referenced from
/// Gleam, and so cannot be pulled into a JavaScript bundle.
///
/// The body is the JavaScript implementation, where there is no filesystem to
/// read TZif files from.
@external(erlang, "gtz_ffi", "host_database")
fn host_database() -> Result(TzDatabase, Nil) {
  Error(Nil)
}

/// Raw native transition facts for one IANA zone, from the host's `Temporal`
/// or `Intl` APIs. The body is the Erlang implementation, which has neither.
@external(javascript, "./gtz_ffi.mjs", "zone_transitions")
fn platform_zone_data(_zone_name: String) -> Result(List(Row), Nil) {
  Error(Nil)
}

/// Each row is
/// `#(transition_start_unix_seconds, utc_offset_seconds, designation)`
/// as reported by the host platform for one offset transition.
type Row =
  #(Int, Int, String)

/// Assemble platform transition rows into the TZif shape `tzif` queries.
///
/// `rows` is never empty: both platform implementations emit a baseline row
/// for the start of their window before any transitions. That matters, because
/// a zone with no offset records at all is exactly the one case `tzif` cannot
/// resolve, and `build` rejects it.
fn build_tzfile(rows: List(Row)) -> parser.TzFile {
  // Heuristic: standard time is the smallest offset observed for the zone; any
  // larger offset is treated as daylight saving time. This holds for the usual
  // "standard / standard + 1h" arrangement.
  let standard =
    rows
    |> list.map(fn(row) { row.1 })
    |> list.reduce(int_min)
    |> result.unwrap(0)

  let ttinfos =
    list.map(rows, fn(row) {
      let isdst = case row.1 > standard {
        True -> 1
        False -> 0
      }
      // desigidx is unused by the query path because designations are supplied
      // as a parallel list here, so 0 is fine.
      parser.TtInfo(utoff: row.1, isdst:, desigidx: 0)
    })

  let fields =
    parser.TzFileFields(
      transition_times: list.map(rows, fn(row) { row.0 }),
      // time_types[i] = i, indexing 1:1 into ttinfos / designations.
      time_types: list.index_map(rows, fn(_, i) { i }),
      ttinfos:,
      designations: list.map(rows, fn(row) { row.2 }),
      leapsecond_values: [],
      standard_or_wall: [],
      ut_or_local: [],
    )

  let count = list.length(rows)

  parser.TzFile(
    header: parser.TzFileHeader(
      version: 2,
      ttisutcnt: 0,
      ttisstdcnt: 0,
      leapcnt: 0,
      timecnt: count,
      typecnt: count,
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
