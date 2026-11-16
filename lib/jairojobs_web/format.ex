defmodule JairojobsWeb.Format do
  @moduledoc """
  Display helpers shared by every screen. Money is formatted here and nowhere
  else (constitution §4.5), and so are times (constitution §4.6).
  """

  # Manila is UTC+8 all year: the Philippines has not used daylight saving
  # since 1990. A fixed offset keeps a time zone database out of the project
  # (spec 004, plan decision 5). If that ever changes, this is the one place.
  @manila_offset_seconds 8 * 60 * 60

  @minute 60
  @hour 60 * @minute
  @day 24 * @hour

  @doc """
  How long ago `at` was, for list rows and status boxes: relative for anything
  under 7 days, the date in Manila after that (design guide, trust signals).

      iex> now = ~U[2026-11-14 12:00:00Z]
      iex> JairojobsWeb.Format.time_ago(~U[2026-11-14 11:40:00Z], now)
      "20 min ago"
      iex> JairojobsWeb.Format.time_ago(~U[2026-11-14 09:00:00Z], now)
      "3 h ago"
      iex> JairojobsWeb.Format.time_ago(~U[2026-11-01 09:00:00Z], now)
      "1 Nov 2026"

  The text is worked out when it is rendered; it does not tick.
  """
  def time_ago(%DateTime{} = at, %DateTime{} = now \\ DateTime.utc_now()) do
    case DateTime.diff(now, at, :second) do
      seconds when seconds < @minute -> "just now"
      seconds when seconds < @hour -> "#{div(seconds, @minute)} min ago"
      seconds when seconds < @day -> "#{div(seconds, @hour)} h ago"
      seconds when seconds < 7 * @day -> "#{div(seconds, @day)} d ago"
      _a_week_or_more -> manila_date(at)
    end
  end

  @doc """
  The date of `at` in Manila time: `~U[2026-11-14 16:00:00Z]` → `"15 Nov 2026"`.
  """
  def manila_date(%DateTime{} = at) do
    at
    |> DateTime.add(@manila_offset_seconds, :second)
    |> Calendar.strftime("%-d %b %Y")
  end

  @doc """
  A monthly salary range in whole pesos (REQ-003-4).

      iex> JairojobsWeb.Format.salary_range(14_000, 16_000)
      "₱14,000–16,000 / month"
      iex> JairojobsWeb.Format.salary_range(14_000, 16_000, :short)
      "₱14,000–16,000/mo"
      iex> JairojobsWeb.Format.salary_range(15_000, 15_000)
      "₱15,000 / month"

  `:long` (the default) is for a listing's page, `:short` for list rows.
  Returns `nil` while either end is missing.
  """
  def salary_range(min, max, style \\ :long)

  def salary_range(min, max, style) when is_integer(min) and is_integer(max) do
    amount = if min == max, do: pesos(min), else: "#{pesos(min)}–#{pesos(max)}"
    "₱" <> amount <> suffix(style)
  end

  def salary_range(_min, _max, _style), do: nil

  defp suffix(:long), do: " / month"
  defp suffix(:short), do: "/mo"

  @doc """
  A whole number of pesos with thousands separators: `14000` → `"14,000"`.
  """
  def pesos(amount) when is_integer(amount) and amount >= 0 do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
