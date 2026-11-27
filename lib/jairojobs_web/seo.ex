defmodule JairojobsWeb.Seo do
  @moduledoc """
  What a public page says about itself in its `<head>`, for the machines that
  read it: chat apps building a link preview (spec 005, REQ-005-8) and search
  engines (REQ-005-9).

  The functions here only build a map; `JairojobsWeb.Layouts.seo/1` writes the
  tags, in the root layout. A page that assigns no `:seo` gets none.

    * `:description` — one plain sentence
    * `:canonical` — the page's one address, in full and with nothing added,
      so the same page reached with extra words in its address is not counted
      twice
    * `:noindex` — the page asks not to be listed in search results
    * `:og` — the text preview a chat app shows
    * `:json_ld` — the job details, in the format search engines publish for
      job postings (schema.org `JobPosting`)

  Everything is taken from the listing as it is now, and only from what the
  public page itself shows. No id, no account, no status.
  """

  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions.Region
  alias JairojobsWeb.Format
  alias JairojobsWeb.ListingComponents
  alias JairojobsWeb.PublicAddress

  # Manila is UTC+8 all year (see `JairojobsWeb.Format`).
  @manila_offset_seconds 8 * 60 * 60

  # The names search engines give the types of work (schema.org `employmentType`).
  @employment_types %{
    full_time: "FULL_TIME",
    part_time: "PART_TIME",
    contract: "CONTRACTOR",
    temporary: "TEMPORARY",
    internship: "INTERN"
  }

  @doc """
  The tags of a list of jobs: the home page for `nil`, or a region's list.

  A list narrowed by words or by a type asks not to be listed: there are
  endlessly many of them and each is a part of a list that is listed. So does
  the list of a hidden region, for as long as it is hidden (spec decision 25).
  Either still states the plain address of the list.
  """
  def list(region, narrowed?) do
    %{
      description:
        "#{list_name(region)}, newest first, each with its salary shown and checked by jairojobs before it is published.",
      canonical: PublicAddress.list_url(region),
      noindex: narrowed? or hidden?(region)
    }
  end

  defp list_name(nil), do: "Jobs across the Philippines"
  defp list_name(%Region{name: name}), do: "Jobs in #{name}"

  defp hidden?(%Region{active: false}), do: true
  defp hidden?(_active_or_every_region), do: false

  @doc """
  The tags of a Published listing's public page.

  The description names the salary, the type, the area and the region. The
  preview a chat app shows is text only, since the site has no images:
  "Barista (full-time) — Kape Isla", then "₱14,000–16,000 / month · Matina,
  Davao City". The salary is in it because it is the first thing a job seeker
  asks (REQ-005-8).

  A listing in a hidden region is treated like any other: only the status
  decides what is public (REQ-005-1).
  """
  def listing(%Listing{} = listing) do
    salary = Format.salary_range(listing.salary_min, listing.salary_max)
    where = "#{listing.area}, #{listing.region.name}"
    type = ListingComponents.employment_type_label(listing.employment_type)

    %{
      description: "#{listing.title} at #{listing.business_name}: #{salary}, #{type}, #{where}.",
      canonical: PublicAddress.listing_url(listing),
      noindex: false,
      # A list, so the tags are written in this order every time.
      og: [
        title: "#{listing.title} — #{listing.business_name}",
        description: "#{salary} · #{where}",
        url: PublicAddress.listing_url(listing),
        type: "website",
        site_name: "jairojobs"
      ],
      json_ld: job_posting(listing)
    }
  end

  @doc """
  The tags of the page that says a job is no longer listed (REQ-005-7): it
  asks not to be listed, and says nothing of the listing.
  """
  def gone, do: %{noindex: true}

  @doc """
  A listing as a schema.org `JobPosting`: the title, the business, the area
  and region, the salary range in PHP per month, the type, the date posted and
  the text (REQ-005-9).

  The date posted is the day of approval, in Manila. No closing date is given,
  because listings do not expire (spec 000), and no identifier, because a
  listing's id is never public (constitution §4.8).
  """
  def job_posting(%Listing{} = listing) do
    %{
      "@context" => "https://schema.org",
      "@type" => "JobPosting",
      "title" => listing.title,
      "description" => description_html(listing),
      "datePosted" => manila_date(listing.published_at),
      "employmentType" => Map.fetch!(@employment_types, listing.employment_type),
      "hiringOrganization" => %{"@type" => "Organization", "name" => listing.business_name},
      "jobLocation" => %{
        "@type" => "Place",
        "address" => %{
          "@type" => "PostalAddress",
          "addressLocality" => listing.area,
          "addressRegion" => listing.region.name,
          "addressCountry" => "PH"
        }
      },
      "baseSalary" => %{
        "@type" => "MonetaryAmount",
        "currency" => "PHP",
        "value" => %{
          "@type" => "QuantitativeValue",
          "minValue" => listing.salary_min,
          "maxValue" => listing.salary_max,
          "unitText" => "MONTH"
        }
      }
    }
  end

  # Search engines read a job's description as HTML. The texts are plain text
  # (REQ-003-4), so each is escaped, and only its line breaks become markup.
  defp description_html(listing) do
    [
      {nil, listing.description},
      {"Requirements", listing.requirements},
      {"Benefits", listing.benefits}
    ]
    |> Enum.filter(fn {_heading, text} -> is_binary(text) end)
    |> Enum.map_join(fn
      {nil, text} -> "<p>#{escape(text)}</p>"
      {heading, text} -> "<p><strong>#{heading}</strong><br>#{escape(text)}</p>"
    end)
  end

  defp escape(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/\r?\n/, "<br>")
  end

  defp manila_date(%DateTime{} = at) do
    at |> DateTime.add(@manila_offset_seconds, :second) |> DateTime.to_date() |> Date.to_iso8601()
  end

  @doc """
  The job details as the text of a `<script type="application/ld+json">`
  block: JSON in which `<`, `>` and `&` are written as escapes, so nothing an
  employer typed, `</script>` included, can end the block or be read as
  markup.
  """
  def encode_json_ld(%{} = json_ld), do: Jason.encode!(json_ld, escape: :html_safe)
end
