defmodule JairojobsWeb.FormatTest do
  use ExUnit.Case, async: true

  alias JairojobsWeb.Format

  describe "salary_range/3" do
    test "REQ-003-4: a range with thousands separators, as shown on a listing's page" do
      assert Format.salary_range(14_000, 16_000) == "₱14,000–16,000 / month"
      assert Format.salary_range(1_000, 1_000_000) == "₱1,000–1,000,000 / month"
    end

    test "REQ-003-4: the short form used in list rows" do
      assert Format.salary_range(14_000, 16_000, :short) == "₱14,000–16,000/mo"
    end

    test "REQ-003-4: same minimum and maximum is allowed" do
      assert Format.salary_range(15_000, 15_000) == "₱15,000 / month"
      assert Format.salary_range(15_000, 15_000, :short) == "₱15,000/mo"
    end

    test "nothing to show while the salary is not filled in" do
      assert Format.salary_range(nil, nil) == nil
      assert Format.salary_range(14_000, nil, :short) == nil
    end
  end

  describe "pesos/1" do
    test "groups thousands" do
      assert Format.pesos(999) == "999"
      assert Format.pesos(1_000) == "1,000"
      assert Format.pesos(1_234_567) == "1,234,567"
    end
  end
end
