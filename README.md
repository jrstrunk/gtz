# gtz
A simple timezone library for Gleam!

[![Package Version](https://img.shields.io/hexpm/v/gtz)](https://hex.pm/packages/gtz)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gtz/)

```sh
gleam add gtz
gleam add gtempo@5
```

This package was written to be used with the [Tempo](https://hexdocs.pm/gtempo/index.html) package, but could be expanded to provide timezone support for other libraries as well! Contributions are welcome! Currently this package is very simple and only supports converting non-naive datetimes to a specific timezone via Tempo; it does not support constructing new datetimes in a specific timezone or assigning a timezone to an existing naive datetime.

Ambiguous datetimes and DST boundries are not handled explicitly by this package, but instead rely on the target timezone package's default handling. It seems like the Elixir package prefers the future time and JavaScript prefers the past time for DST boundries. Once ambiguous datetimes are worked out to be a little more explicit or obvious in this package, there will probably be a v1 release.

Supports both the Erlang and JavaScript targets.

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
