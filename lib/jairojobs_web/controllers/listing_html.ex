defmodule JairojobsWeb.ListingHTML do
  @moduledoc """
  The pages rendered by `JairojobsWeb.ListingController` (spec 005).
  """
  use JairojobsWeb, :html

  import JairojobsWeb.ListingComponents

  alias JairojobsWeb.Format
  alias JairojobsWeb.PublicAddress

  embed_templates "listing_html/*"
end
