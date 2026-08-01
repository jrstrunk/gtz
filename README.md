# gtz

Simple Gleam time zone conversions for all targets, built on top of `tzif`!

[![Package Version](https://img.shields.io/hexpm/v/gtz)](https://hex.pm/packages/gtz)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gtz/)

```sh
gleam add gtz
gleam add gleam_time
```

Converting an ambiguous calendar time to a timestamp assumes the first occurrence of the ambiguous time. Accounting for leap seconds depends on the dataset. If you need more control over how ambiguous dates are handled or the designation of the given time in the zone, use the `tzif` package directly.

The `build` function reads the host's own time zone data. When the host has none, or when it is somewhere other than where the host usually stores it, you can supply a database yourself with `build_from`.

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

## Providing your own time zone database

On the Erlang target, `build` reads the operating system's TZif database at `/usr/share/zoneinfo`. A host with no zoneinfo tree there, such as a scratch container image, has no zone to recognize and every name fails. On JavaScript, information for the given zone is derived from the host's native `Temporal` and `Intl` APIs.

Use `build_from` when working in a bare environment (such as a scratch container image on the Erlang target), a host that keeps its zoneinfo somewhere other than `/usr/share/zoneinfo`, or you need precise control over the dataset.

The `zones` package ships a prebuilt database and needs no files at all, which suits bare environments.

```sh
gleam add zones
```

```gleam
import zones

let assert Ok(zone) = gtz.build_from("Asia/Kolkata", zones.database())
```

`tzif` itself can load from any directory, which suits a non-standard location or a self-compiled database.

```sh
gleam add tzif
```

```gleam
import tzif/database

let assert Ok(db) = database.load_from_path("/opt/zoneinfo")
let assert Ok(zone) = gtz.build_from("Asia/Kolkata", db)
```

Further documentation can be found at <https://hexdocs.pm/gtz>.

## Development

```sh
gleam test                      # Run the tests on Erlang
gleam test --target javascript  # Run the tests on JavaScript
```
