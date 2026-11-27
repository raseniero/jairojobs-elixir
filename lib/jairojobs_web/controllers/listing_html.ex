defmodule JairojobsWeb.ListingHTML do
  @moduledoc """
  The pages rendered by `JairojobsWeb.ListingController` (spec 005).
  """
  use JairojobsWeb, :html

  import JairojobsWeb.ListingComponents

  embed_templates "listing_html/*"
end
