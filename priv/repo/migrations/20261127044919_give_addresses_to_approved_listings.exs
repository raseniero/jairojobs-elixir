defmodule Jairojobs.Repo.Migrations.GiveAddressesToApprovedListings do
  use Ecto.Migration

  # spec 005 — REQ-005-6, plan decision 6. Data only.
  #
  # A listing gets its public address when it is approved. Listings approved
  # before spec 005 have none, so each one gets it here: every listing that has
  # `published_at` and no slug (Published, Closed and Taken down alike), oldest
  # approval first, so the earliest listing with a title gets the slug without a
  # number.
  #
  # The slug rule is copied into this file on purpose. A migration must keep
  # working after the app's code changes, so it calls no module of the app. The
  # rule is the one in `Jairojobs.Listings.Slug` as it was when this was written;
  # it only ever applies to listings from before spec 005.
  #
  # Safe to run twice: a listing that already has a slug is left alone.

  @max_length 60

  def up do
    %{rows: taken_rows} = repo().query!("SELECT region_id, slug FROM listing_addresses")

    taken =
      Enum.reduce(taken_rows, %{}, fn [region_id, slug], taken ->
        Map.update(taken, region_id, MapSet.new([slug]), &MapSet.put(&1, slug))
      end)

    %{rows: listings} =
      repo().query!("""
      SELECT id, region_id, title FROM listings
      WHERE published_at IS NOT NULL AND slug IS NULL
      ORDER BY published_at, id
      """)

    Enum.reduce(listings, taken, fn [id, region_id, title], taken ->
      in_region = Map.get(taken, region_id, MapSet.new())
      slug = title |> from_title() |> free(in_region)
      now = DateTime.utc_now()

      repo().query!(
        """
        INSERT INTO listing_addresses (id, listing_id, region_id, slug, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $5)
        """,
        [Ecto.UUID.bingenerate(version: 7), id, region_id, slug, now]
      )

      # `updated_at` is left alone: the listing itself did not change.
      repo().query!("UPDATE listings SET slug = $1 WHERE id = $2", [slug, id])

      Map.put(taken, region_id, MapSet.put(in_region, slug))
    end)
  end

  # Nothing to undo: rolling back the migration before this one drops the column
  # and the table.
  def down, do: :ok

  defp from_title(title) do
    slug =
      title
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> cut(@max_length)

    if slug == "", do: "job", else: slug
  end

  defp free(wanted, taken) do
    if MapSet.member?(taken, wanted), do: numbered(wanted, taken, 2), else: wanted
  end

  defp numbered(wanted, taken, number) do
    suffix = "-#{number}"
    slug = cut(wanted, @max_length - byte_size(suffix)) <> suffix

    if MapSet.member?(taken, slug), do: numbered(wanted, taken, number + 1), else: slug
  end

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
