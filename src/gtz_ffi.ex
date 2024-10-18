defmodule GTZ_FFI do
  def calculate_offset(year, month, day, hour, minute, second, timezone) do
    # Create a DateTime from the input in UTC
    naive_datetime = NaiveDateTime.new!(year, month, day, hour, minute, second)
    utc_datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")

    # Convert the UTC DateTime to the target timezone
    tz_datetime = DateTime.shift_zone!(utc_datetime, timezone, Tz.TimeZoneDatabase)

    # Calculate the offset in seconds
    offset_seconds = tz_datetime.utc_offset + tz_datetime.std_offset

    trunc(offset_seconds / 60)
  end

  def is_valid_timezone(timezone) do
    case DateTime.now(timezone, Tz.TimeZoneDatabase) do
      {:ok, _datetime} -> true
      {:error, _reason} -> false
    end
  end
end
