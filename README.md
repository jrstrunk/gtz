# gtz
A timezone data provider for Gleam!

[![Package Version](https://img.shields.io/hexpm/v/gtz)](https://hex.pm/packages/gtz)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gtz/)

```sh
gleam add gtz
# Choose which package to use for other time functionality
gleam add gtempo
gleam add gleam_time
```

This package has functions to be used with the [gtempo](https://hexdocs.pm/gtempo/index.html) package and the [gleam_time](https://hexdocs.pm/gleam_time/index.html) package. Currently this package is very simple: it only supports converting non-naive datetimes to a specific timezone via `gtempo`, and calculating an offset given a timestamp and time zone via the `gleam_time` types. Contributions are welcome!

Supports both the Erlang and JavaScript targets. On Erlang the timezone data comes from the operating system's TZif files (typically `/usr/share/zoneinfo`) via the `tzif` package, loaded once and cached in a persistent term; on JavaScript it comes from the native `Intl` API.

#### Calculating Offsets In a Time Zone
```gleam
import gleam/time/timestamp
import gtz

let my_ts = timestamp.from_unix_seconds(1_729_257_776)

let assert Ok(ny_offset) = 
  gtz.calculate_offset(my_ts, in: "America/New_York")

// Now that we have the offset for the timestamp in the desired time zone, we 
// can convert it to a calendar date and time
timestamp.to_calendar(my_ts, ny_offset)
// -> #(
//   calendar.Date(2024, calendar.October, 18),
//   calendar.TimeOfDay(9, 22, 56, 0)
// )
```

#### Converting DateTimes to the Local Timezone
```gleam
import gtz
import tempo/datetime

pub fn main() {
  let assert Ok(local_tz) = gtz.local_name() |> gtz.timezone

  datetime.from_unix_utc(1_729_257_776)
  |> datetime.to_timezone(local_tz)
  |> datetime.to_string
}
// -> "2024-10-18T14:22:56.000+01:00"
```

#### Converting DateTimes to a Specific Timezone

```gleam
import gtz
import tempo/datetime

pub fn main() {
  let assert Ok(tz) = gtz.timezone("America/New_York")

  datetime.literal("2024-01-03T05:30:02.334Z")
  |> datetime.to_timezone(tz)
  |> datetime.to_string
}
// -> "2024-01-03T00:30:02.334-05:00"
```

Further documentation can be found at <https://hexdocs.pm/gtz>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
