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

Ambiguous datetimes and DST boundaries are not handled explicitly by this package, but instead rely on the target timezone package's default handling. It seems like the Elixir package prefers the future time and JavaScript prefers the past time for DST boundaries. Once ambiguous datetimes are worked out to be a little more explicit or obvious in this package, there will probably be a v1 release.

Supports both the Erlang (via a dependency on the Elixir `tz` and `timex` libraries) and JavaScript (via the native `Intl` API) targets.

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
