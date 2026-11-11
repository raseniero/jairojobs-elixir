defmodule Jairojobs.Pesos do
  @moduledoc """
  An amount of money in **whole pesos** (spec 003).

  In memory and in forms the value is an integer number of pesos (`14000`).
  In the database it is an integer number of **centavos** (`1400000`), as the
  constitution requires (§4.5). This type is the one place the two meet.

  Casting accepts an integer, or a string of digits with optional thousands
  commas and an optional leading `₱` — `"14000"`, `"14,000"`, `"₱14,000"`.
  Amounts with centavos (`"14000.50"`) and anything else are refused.
  """
  use Ecto.Type

  @message "must be a whole number of pesos"

  @impl true
  def type, do: :integer

  @impl true
  def cast(pesos) when is_integer(pesos) and pesos >= 0, do: {:ok, pesos}

  def cast(text) when is_binary(text) do
    digits = text |> String.trim() |> String.trim_leading("₱") |> String.trim()

    if digits =~ ~r/\A(\d+|\d{1,3}(,\d{3})+)\z/ do
      {:ok, digits |> String.replace(",", "") |> String.to_integer()}
    else
      {:error, message: @message}
    end
  end

  def cast(_other), do: {:error, message: @message}

  @impl true
  def load(centavos) when is_integer(centavos), do: {:ok, div(centavos, 100)}

  @impl true
  def dump(pesos) when is_integer(pesos), do: {:ok, pesos * 100}
  def dump(_other), do: :error
end
