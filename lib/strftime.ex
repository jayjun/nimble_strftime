defmodule Strftime do
  @moduledoc """
  Library for simple datetime formatting based on the strftime format found on UNIX-like systems

  ## Formatting syntax
  The formatting syntax for strftime is a sequence of characters in the following format
  `%<padding><width><format>`
  * `%`: indicates the start of a formatted section
  * `<padding>`: is an option to set the padding of the formatted section and accepts the following options
  * `<width>`: a number indicating the minimun size of the formatted section
  * `<format>`: the format iself, dictates what info is shown on this formatted section

  ### Accepted padding options
    * `-`: no padding, removes all padding from the format
    * `_`: pad with spaces
    * `0`: pad with zeroes

  ### Accepted formats
  the accepted formats are as follows, any other character will be interpreted literally and won't be formatted
  * `%` -  Literally just the `%` char
  * `a` -  Abbreviated name of the day
  * `A` -  Name of the day
  * `b` -  Abbreviated name of the month
  * `B` -  Name of the month
  * `c` -  Preferred datetime representation
  * `d` -  Day of the month
  * `f` -  Microseconds
  * `H` -  Hour in Military Time(24 hours)
  * `I` -  Hour in Regular Time(12 hours)
  * `J` -  Day of the year
  * `m` -  Month
  * `M` -  Minute
  * `p` -  Period of the day("AM" and "PM") in uppercase
  * `P` -  Period of the day("am" and "pm") in lowercase
  * `q` -  Quarter of the year
  * `S` -  Second
  * `u` -  Day of the week
  * `x` -  Preferred date
  * `X` -  Preferred time
  * `y` -  Year in two digits
  * `Y` -  Year
  * `z` -  Time zone offset from UTC(blank if in naive time)
  * `Z` -  Time zone abbreviation(Blank if naive)
  """
  alias Strftime.FormatStream
  alias Strftime.FormatOptions

  @empty_date %{
    day: 1,
    hour: 0,
    microsecond: {0, 0},
    minute: 0,
    month: 1,
    second: 0,
    year: 0,
    std_offset: 0,
    time_zone: "",
    utc_offset: 0,
    zone_abbr: ""
  }

  @doc """
    Formats received datetime into a String
  """
  @spec format(
          Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(),
          String.t(),
          FormatOptions.options()
        ) :: String.t()
  def format(date_or_time_or_datetime, string_format, format_options \\ []) do
    datetime =
      @empty_date
      |> Map.merge(date_or_time_or_datetime)

    parse(string_format, datetime, Map.new(format_options))
  end

  defp parse(data, datetime, format_options, acc \\ "")
  defp parse("", _datetime, _format_options, acc), do: acc

  defp parse("%" <> rest, datetime, format_options, acc),
    do: exec_stream(rest, datetime, acc, format_options)

  defp parse(<<char::binary-1, rest::binary>>, datetime, format_options, acc) do
    parse(rest, datetime, format_options, acc <> char)
  end

  defp exec_stream(data, datetime, acc, format_options) do
    {format_stream, remaining} = stream(data, %FormatStream{})
    options_struct = Map.merge(%FormatOptions{}, format_options)

    parse(
      remaining,
      datetime,
      format_options,
      acc <> apply_stream(format_stream, datetime, options_struct)
    )
  end

  @spec stream(String.t(), FormatStream.t()) :: {FormatStream.t(), String.t()}
  defp stream("", format_stream), do: {format_stream, ""}

  defp stream("-" <> rest, format_stream = %{pad: nil}) do
    stream(rest, %{format_stream | pad: "-", section: format_stream.section <> "-"})
  end

  defp stream("0" <> rest, format_stream = %{pad: nil}) do
    stream(rest, %{format_stream | pad: "0", section: format_stream.section <> "0"})
  end

  defp stream("_" <> rest, format_stream = %{pad: nil}) do
    stream(rest, %{format_stream | pad: " ", section: format_stream.section <> "_"})
  end

  defp stream(<<digit::utf8, rest::binary>>, format_stream = %{pad: pad})
      when digit > 47 and digit < 58 do
    new_width =
      case pad do
        "-" -> 0
        _ -> (format_stream.width || 0) * 10 + (digit - 48)
      end

    stream(rest, %{format_stream | width: new_width, section: format_stream.section <> <<digit>>})
  end

  defp stream(<<format::binary-1, rest::binary>>, format_stream) do
    {%{format_stream | format: format, section: format_stream.section <> format}, rest}
  end
  defp apply_stream(format_stream = %{format: format, pad: nil}, datetime, format_options) do
    apply_stream(%{format_stream | pad: default_pad(format)}, datetime, format_options)
  end

  defp apply_stream(format_stream = %{format: format, width: nil}, datetime, format_options) do
    apply_stream(%{format_stream | width: default_width(format)}, datetime, format_options)
  end

  defp apply_stream(
         format_stream = %FormatStream{format: format, width: width, pad: pad},
         datetime,
         format_options
       ) do
    case format do
      # Literal `%`
      "%" ->
        "%"

      # Abbreviated name of day
      "a" ->
        datetime
        |> Date.day_of_week()
        |> FormatOptions.day_of_week_name_abbreviated(format_options)

      # Full name of day
      "A" ->
        datetime
        |> Date.day_of_week()
        |> FormatOptions.day_of_week_name(format_options)

      # Abbreviated month name
      "b" ->
        FormatOptions.month_name_abbreviated(datetime.month(), format_options)

      # Full month name
      "B" ->
        FormatOptions.month_name(datetime.month(), format_options)

      # Preferred date+time representation
      "c" ->
        parse(format_options.preferred_datetime, datetime, format_options)

      # Day of the month
      "d" ->
        datetime.day()

      # Microseconds
      "f" ->
        elem(datetime.microsecond(), 0)

      # Hour using a 24-hour clock
      "H" ->
        datetime.hour()

      # Hour using a 12-hour clock
      "I" ->
        rem(datetime.hour() + 23, 12) + 1

      # Day of the year
      "j" ->
        Date.day_of_year(datetime)

      # Month
      "m" ->
        datetime.month()

      # Minute
      "M" ->
        datetime.minute()

      # “AM” or “PM” (noon is “PM”, midnight as “AM”)
      "p" ->
        datetime.hour()
        |> am_pm(format_options)
        |> String.upcase()

      # “am” or “pm” (noon is “pm”, midnight as “am”)
      "P" ->
        datetime.hour()
        |> am_pm(format_options)
        |> String.downcase()

      # Quarter
      "q" ->
        Date.quarter_of_year(datetime)

      # Second
      "S" ->
        datetime.second()

      # Day of the week
      "u" ->
        Date.day_of_week(datetime)

      # Preferred date (without time) representation
      "x" ->
        parse(format_options.preferred_date, datetime, format_options)

      # Preferred time (without date) representation
      "X" ->
        parse(format_options.preferred_time, datetime, format_options)

      # Year as 2-digits
      "y" ->
        rem(datetime.year(), 100)

      # Year
      "Y" ->
        datetime.year()

      # +hhmm/-hhmm time zone offset from UTC (empty string if naive)
      "z" ->
        case datetime do
          %DateTime{} -> "#{datetime.utc_offset()}, #{datetime.std_offset()}"
          _ -> ""
        end

      # Time zone abbreviation (empty string if naive)
      "Z" ->
        datetime.zone_abbr()

      _ ->
        format_stream.section
    end
    |> to_string()
    |> String.pad_leading(width, pad)
  end

  defp am_pm(hour, format_options) when hour > 11 do
    FormatOptions.pm_name(format_options)
  end

  defp am_pm(hour, format_options) when hour < 11 do
    FormatOptions.am_name(format_options)
  end

  defp default_pad(format) do
    case format do
      format when format in ~w(a A b B p P Z) -> " "
      _ -> "0"
    end
  end

  defp default_width(format) do
    case format do
      format when format in ~w(d H I m M S u y) -> 2
      "j" -> 3
      "Y" -> 4
      _ -> 0
    end
  end
end
