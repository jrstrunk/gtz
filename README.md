# gtz
A timezone data provider for Gleam!

[![Package Version](https://img.shields.io/hexpm/v/gtz)](https://hex.pm/packages/gtz)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gtz/)

```sh
gleam add gtz
gleam add gleam_time
```

The whole API is one type and three functions. Build a `TimeZone` from an IANA
zone name, then convert `gleam_time` timestamps to and from calendar dates with
it. The conversions themselves are [`tzif`](https://hexdocs.pm/tzif/)'s; what
this package adds is getting a usable time zone database in place on both the
Erlang and JavaScript targets without the caller having to think about it.

#### Converting a Timestamp to a Date and Time

Every instant has a wall clock reading in every zone, so this direction cannot
fail once you hold a `TimeZone`, and it does not return a `Result`.

```gleam
import gleam/time/timestamp
import gtz

let assert Ok(zone) = gtz.build("America/New_York")

timestamp.from_unix_seconds(1_729_257_776)
|> gtz.to_calendar(zone)
// -> #(
//   calendar.Date(2024, calendar.October, 18),
//   calendar.TimeOfDay(9, 22, 56, 0),
//   duration.seconds(-14_400),
// )
```

#### Converting a Date and Time Back to a Timestamp

Daylight saving time makes this direction partial. When the wall clock time is
ambiguous, because the clocks went back and it happened twice, the first
occurrence is returned. When it never existed at all, because the clocks went
forward over it, `Error(Nil)` is returned.

```gleam
import gleam/time/calendar
import gtz

let assert Ok(zone) = gtz.build("America/New_York")

gtz.from_calendar(
  calendar.Date(2024, calendar.October, 18),
  calendar.TimeOfDay(9, 22, 56, 0),
  zone,
)
// -> Ok(timestamp.from_unix_seconds(1_729_257_776))
```

#### Using the Host's Time Zone

```gleam
let assert Ok(zone) = gtz.local_name() |> gtz.build
```

## Where the data comes from

**Erlang.** The operating system's TZif files (typically `/usr/share/zoneinfo`)
are read via `tzif`, once, and memoized in a persistent term. If the host has no
zoneinfo tree, such as on a scratch container image, the prebuilt database from
the [`zones`](https://hexdocs.pm/zones/) package is used instead. `zones` is only
ever referenced from the Erlang FFI, so its several megabytes are never
reachable from a JavaScript build.

**JavaScript.** There is no filesystem to read TZif files from, so a lean
database covering just the requested zone is synthesized from the host's own
time zone engine and cached. Where `Temporal` is available its transitions are
read directly; otherwise the same transitions are found by scanning with `Intl`,
which every engine has had for a decade. Offsets are exact either way.
`designation` is the abbreviation `Intl` reports ("EDT", or a numeric form like
"GMT-4" where the locale data has no name), `is_dst` is inferred by treating any
offset above the zone's smallest as daylight saving, and leap seconds are
ignored. Only 1970 through 2100 is covered; earlier timestamps resolve to the
earliest known offset.

Further documentation can be found at <https://hexdocs.pm/gtz>.

## Development

```sh
gleam test                      # Run the tests on Erlang
gleam test --target javascript  # Run the tests on JavaScript
```
