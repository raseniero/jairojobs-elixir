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

  # spec 004 — the one time helper (constitution §4.6).
  describe "time_ago/2" do
    @now ~U[2026-11-14 12:00:00.000000Z]

    defp ago(seconds), do: Format.time_ago(DateTime.add(@now, -seconds, :second), @now)

    test "under a minute" do
      assert ago(0) == "just now"
      assert ago(59) == "just now"
    end

    test "minutes, hours and days" do
      assert ago(60) == "1 min ago"
      assert ago(20 * 60) == "20 min ago"
      assert ago(59 * 60 + 59) == "59 min ago"
      assert ago(3600) == "1 h ago"
      assert ago(3 * 3600) == "3 h ago"
      assert ago(23 * 3600 + 3599) == "23 h ago"
      assert ago(86_400) == "1 d ago"
      assert ago(6 * 86_400 + 86_399) == "6 d ago"
    end

    test "from 7 days on, the date" do
      assert ago(7 * 86_400) == "7 Nov 2026"
      assert ago(40 * 86_400) == "5 Oct 2026"
    end

    test "a time slightly in the future (clock skew) is just now" do
      assert ago(-5) == "just now"
    end
  end

  describe "manila_date/1" do
    test "a date in Manila time, which is UTC+8 all year" do
      assert Format.manila_date(~U[2026-11-14 03:00:00Z]) == "14 Nov 2026"
      assert Format.manila_date(~U[2026-07-01 03:00:00Z]) == "1 Jul 2026"
    end

    test "late in the UTC day it is already the next day in Manila" do
      assert Format.manila_date(~U[2026-11-14 15:59:59Z]) == "14 Nov 2026"
      assert Format.manila_date(~U[2026-11-14 16:00:00Z]) == "15 Nov 2026"
      assert Format.manila_date(~U[2026-12-31 20:00:00Z]) == "1 Jan 2027"
    end
  end
end
