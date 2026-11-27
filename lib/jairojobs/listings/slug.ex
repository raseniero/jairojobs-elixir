defmodule Jairojobs.Listings.Slug do
  @moduledoc """
  The slug in a listing's public address, `/jobs/<region>/<slug>` (spec 005,
  REQ-005-6).

  Pure functions: they read and write nothing. `Jairojobs.Listings` decides
  when a listing gets a slug (at approval, and when an Admin moves a Published
  listing to another region) and which slugs are already taken.
  """

  alias Jairojobs.Regions.Region

  @max_length 60
  @fallback "job"

  @doc """
  The slug a title gives: lowercase ASCII letters, digits and hyphens, by the
  same rule as a region's slug (REQ-002-2), at most 60 characters. A longer
  one is cut at a word where there is one to cut at. A title that leaves
  nothing usable gives `"job"`, so approval never fails over an address.

      iex> Jairojobs.Listings.Slug.from_title("Café Staff — ₱500/day!!")
      "cafe-staff-500-day"
      iex> Jairojobs.Listings.Slug.from_title("₱₱₱₱₱")
      "job"
  """
  def from_title(title) when is_binary(title) do
    case title |> Region.slugify() |> cut(@max_length) do
      "" -> @fallback
      slug -> slug
    end
  end

  @doc """
  `wanted` if no slug in `taken` is the same, otherwise `wanted` with the
  lowest free number from 2: `barista-2`, `barista-3`. `taken` is every slug a
  listing has or ever had in the region.

  The number is added to `wanted` as it is. With its number the slug is still
  at most 60 characters: the words are cut further to make room.

      iex> Jairojobs.Listings.Slug.free("barista", ["barista", "barista-2"])
      "barista-3"
  """
  def free(wanted, taken) when is_binary(wanted) do
    taken = MapSet.new(taken)
    if MapSet.member?(taken, wanted), do: numbered(wanted, taken, 2), else: wanted
  end

  defp numbered(wanted, taken, number) do
    suffix = "-#{number}"
    slug = cut(wanted, @max_length - byte_size(suffix)) <> suffix

    if MapSet.member?(taken, slug), do: numbered(wanted, taken, number + 1), else: slug
  end

  # A slug is ASCII, so bytes are characters. When the cut falls inside a word
  # and an earlier hyphen exists, the cut goes back to that hyphen.
  defp cut(slug, max) when byte_size(slug) <= max, do: slug

  defp cut(slug, max) do
    head = binary_part(slug, 0, max)

    whole_words =
      if binary_part(slug, max, 1) == "-" do
        head
      else
        case :binary.matches(head, "-") do
          [] -> head
          hyphens -> binary_part(head, 0, hyphens |> List.last() |> elem(0))
        end
      end

    String.trim_trailing(whole_words, "-")
  end
end
