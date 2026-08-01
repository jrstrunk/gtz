# gtz
Simple Gleam time zone conversions for all targets!

[![Package Version](https://img.shields.io/hexpm/v/gtz)](https://hex.pm/packages/gtz)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gtz/)

```sh
gleam add gtz
gleam add gleam_time
```

Simple Gleam time zone conversions for all targets, built on top of `tzif`.
Converting an ambiguous calendar time to a timestamp assumes the first
occurrence of the ambiguous time. Accounting for [the current 27] leap seconds
depends on the host's dataset. If you need more control over where the time zone
data comes from, how ambiguous dates are handled, how leap seconds are accounted
for, or the designation of the given time in the zone, use the very nice `tzif`
and/or `zones` packages directly.

```gleam
import gleam/time/timestamp
import gtz

let zone_name = gtz.local_name() // "Asia/Kolkata"
let assert Ok(zone) = gtz.build(zone_name)

timestamp.from_unix_seconds(1_729_257_776)
|> gtz.to_calendar(zone)
// -> #(
//   calendar.Date(2024, calendar.October, 18),
//   calendar.TimeOfDay(18, 52, 56, 0),
//   duration.seconds(19_800),
// )
```

Further documentation can be found at <https://hexdocs.pm/gtz>.

## Development

```sh
gleam test                      # Run the tests on Erlang
gleam test --target javascript  # Run the tests on JavaScript
```
