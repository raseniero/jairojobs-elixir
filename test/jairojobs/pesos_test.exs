defmodule Jairojobs.PesosTest do
  use ExUnit.Case, async: true

  alias Jairojobs.Pesos

  describe "cast/1" do
    test "REQ-003-4: accepts whole pesos as an integer or as digits" do
      assert Pesos.cast(14_000) == {:ok, 14_000}
      assert Pesos.cast("14000") == {:ok, 14_000}
      assert Pesos.cast(" 14000 ") == {:ok, 14_000}
    end

    test "REQ-003-4: accepts thousands commas and a peso sign" do
      assert Pesos.cast("14,000") == {:ok, 14_000}
      assert Pesos.cast("₱14,000") == {:ok, 14_000}
      assert Pesos.cast("₱ 1,000,000") == {:ok, 1_000_000}
    end

    test "REQ-003-4: salary must be a real monthly amount — no centavos, no text" do
      for bad <- ["14000.50", "14000.00", "abc", "14k", "-5", "1,00", "14 000", 14_000.0, -1] do
        assert {:error, [message: "must be a whole number of pesos"]} = Pesos.cast(bad)
      end
    end
  end

  describe "dump/1 and load/1" do
    test "stores centavos and reads back pesos (constitution §4.5)" do
      assert Pesos.dump(14_000) == {:ok, 1_400_000}
      assert Pesos.load(1_400_000) == {:ok, 14_000}
      assert Pesos.dump("14000") == :error
    end
  end
end
