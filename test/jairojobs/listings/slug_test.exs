defmodule Jairojobs.Listings.SlugTest do
  use ExUnit.Case, async: true

  alias Jairojobs.Listings.Slug

  @format ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  describe "from_title/1 (REQ-005-6)" do
    test "lowercase letters, digits and hyphens, by the rule a region's slug follows" do
      assert Slug.from_title("Barista (full-time)") == "barista-full-time"
      assert Slug.from_title("Software Engineer") == "software-engineer"
    end

    test "unusual characters are dropped, accents are flattened" do
      assert Slug.from_title("Café Staff — ₱500/day!!") == "cafe-staff-500-day"
    end

    test "a title that leaves nothing usable gives \"job\"" do
      assert Slug.from_title("₱₱₱₱₱") == "job"
      assert Slug.from_title("— !! —") == "job"
    end

    test "a short title is not cut" do
      title = "Customer Service Representative for the Night Shift"
      assert Slug.from_title(title) == "customer-service-representative-for-the-night-shift"
    end

    test "a long title is cut at a word, at most 60 characters" do
      title =
        "Customer Service Representative for the Night Shift at the Lanang Call Centre Davao"

      # The 60th character falls inside "lanang", so the cut goes back to the hyphen before it.
      assert Slug.from_title(title) ==
               "customer-service-representative-for-the-night-shift-at-the"
    end

    test "a cut that falls exactly between two words keeps all 60 characters" do
      title = String.duplicate("abcde ", 9) <> "abcdef tail"
      slug = Slug.from_title(title)

      assert String.length(slug) == 60
      assert String.ends_with?(slug, "-abcdef")
    end

    test "one long word with no hyphen to go back to is cut at 60" do
      assert Slug.from_title(String.duplicate("a", 100)) == String.duplicate("a", 60)
    end

    test "every result fits the address format" do
      for title <- ["Barista (full-time)", "  Cook  ", "A-B--C", "₱₱₱₱₱", "Nurse — Clinic"] do
        assert Slug.from_title(title) =~ @format
      end
    end
  end

  describe "free/2 (REQ-005-6)" do
    test "the wanted slug when nothing has it" do
      assert Slug.free("barista-full-time", []) == "barista-full-time"
      assert Slug.free("barista-full-time", ["cashier", "barista"]) == "barista-full-time"
    end

    test "a clash gets the number 2" do
      assert Slug.free("barista-full-time", ["barista-full-time"]) == "barista-full-time-2"
    end

    test "then 3, and so on" do
      taken = ["barista-full-time", "barista-full-time-2"]
      assert Slug.free("barista-full-time", taken) == "barista-full-time-3"

      taken = ["job" | Enum.map(2..11, &"job-#{&1}")]
      assert Slug.free("job", taken) == "job-12"
    end

    test "the lowest free number, when a number in between is free" do
      taken = ["barista-full-time", "barista-full-time-3"]
      assert Slug.free("barista-full-time", taken) == "barista-full-time-2"
    end

    test "the number is added to the wanted slug as it is, also when that ends in a number" do
      assert Slug.free("shift-2", ["shift-2"]) == "shift-2-2"
    end

    test "with its number a slug is still at most 60 characters" do
      wanted = "customer-service-representative-for-the-night-shift-at-the"
      assert String.length(wanted) == 58

      slug = Slug.free(wanted, [wanted])

      # "-2" would make 60, which fits.
      assert slug == wanted <> "-2"

      sixty = String.duplicate("abcde-", 9) <> "abcdef"
      assert String.length(sixty) == 60

      slug = Slug.free(sixty, [sixty])

      assert String.length(slug) <= 60
      assert String.ends_with?(slug, "-2")
      assert slug =~ @format
      # The words were cut at a word to make room.
      assert slug == String.duplicate("abcde-", 8) <> "abcde-2"
    end

    test "a long single word makes room for its number too" do
      word = String.duplicate("a", 60)
      assert Slug.free(word, [word]) == String.duplicate("a", 58) <> "-2"
    end

    test "accepts any enumerable of taken slugs" do
      assert Slug.free("cook", MapSet.new(["cook"])) == "cook-2"
    end
  end
end
