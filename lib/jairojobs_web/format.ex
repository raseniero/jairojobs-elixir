defmodule JairojobsWeb.Format do
  @moduledoc """
  Display helpers shared by every screen. Money is formatted here and nowhere
  else (constitution §4.5).
  """

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
