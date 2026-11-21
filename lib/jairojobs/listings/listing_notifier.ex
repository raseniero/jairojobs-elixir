defmodule Jairojobs.Listings.ListingNotifier do
  @moduledoc """
  The emails about a listing (spec 004): one to its owner for each Admin
  decision on it (REQ-004-9), and one to each Admin when a listing is submitted
  (REQ-004-10).

  Plain text, from the site's one sender (ADR-0005). An email names the
  listing by its title and carries the Admin's reason where there is one. The
  email to Admins adds the business name and the region. Nothing else the
  Employer wrote is included.
  """
  import Swoosh.Email

  alias Jairojobs.Accounts.User
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Mailer

  # The short names of a listing's parts, in the order the form shows them
  # (REQ-004-9): the form's labels without their hints.
  @part_names [
    title: "Job title",
    region_id: "Region",
    area: "Area",
    salary_min: "Salary",
    salary_max: "Salary",
    employment_type: "Type",
    schedule: "Schedule",
    description: "About the job",
    requirements: "Requirements",
    benefits: "Benefits",
    business_name: "Business name",
    business_about: "About the business"
  ]

  @doc """
  The short names of the changed `fields`, each once, in the form's order:
  `[:area, :salary_max, :salary_min]` → `["Area", "Salary"]`.
  """
  def part_names(fields) do
    for({field, name} <- @part_names, field in fields, do: name) |> Enum.uniq()
  end

  @doc """
  Tells the owner their listing was approved and is published.
  """
  def deliver_approved(%User{} = owner, %Listing{} = listing, url) do
    deliver(owner.email, "Your listing is published: #{listing.title}", """
    Hi,

    Your listing "#{listing.title}" was approved and is published on jairojobs.

    It stays up until you close it. Close it when the job is filled:

    #{url}
    """)
  end

  @doc """
  Tells the owner their listing was not approved, with the Admin's reason.
  """
  def deliver_rejected(%User{} = owner, %Listing{} = listing, url) do
    deliver(owner.email, "Your listing needs changes: #{listing.title}", """
    Hi,

    Your listing "#{listing.title}" was not approved yet. This is what needs to change:

    #{quoted(listing.rejection_reason)}

    You can edit it and send it again:

    #{url}
    """)
  end

  @doc """
  Tells the owner their published listing was taken down, with the Admin's reason.
  """
  def deliver_taken_down(%User{} = owner, %Listing{} = listing, url) do
    deliver(owner.email, "Your listing was taken down: #{listing.title}", """
    Hi,

    Your listing "#{listing.title}" was taken down and is no longer public. The reason:

    #{quoted(listing.takedown_reason)}

    This cannot be undone. To list the job again, post a new listing. You can still see
    this one here:

    #{url}
    """)
  end

  @doc """
  Tells the owner which parts of their listing an Admin changed, by name. The
  old and new wording are not quoted.
  """
  def deliver_edited(%User{} = owner, %Listing{} = listing, changed_fields, url) do
    parts = changed_fields |> part_names() |> Enum.map_join("\n", &"  - #{&1}")

    deliver(owner.email, "We edited your listing: #{listing.title}", """
    Hi,

    jairojobs made a small fix to your listing "#{listing.title}". These parts changed:

    #{parts}

    Nothing else was changed. Open the listing to see how it reads now:

    #{url}
    """)
  end

  @doc """
  Tells an Admin that a listing is waiting for approval. `listing` must have
  its region loaded.
  """
  def deliver_submitted(%User{} = admin, %Listing{} = listing, url) do
    deliver(admin.email, "A listing is waiting for approval: #{listing.title}", """
    Hi,

    A listing is waiting for approval on jairojobs:

      "#{listing.title}"
      #{listing.business_name} · #{listing.region.name}

    Read it and decide:

    #{url}
    """)
  end

  defp quoted(text) do
    text |> String.split("\n") |> Enum.map_join("\n", &"    #{&1}")
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:jairojobs, :mailer_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
