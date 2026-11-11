defmodule JairojobsWeb.ListingComponents do
  @moduledoc """
  Components for showing a Listing (spec 003; reused by specs 004 and 005).
  """
  use Phoenix.Component

  @status_labels %{
    draft: "Draft",
    pending: "Waiting for approval",
    published: "Live",
    rejected: "Needs changes",
    closed: "Closed",
    taken_down: "Taken down"
  }

  @doc """
  The words an owner sees for a listing status (spec 003, lifecycle table).
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @doc """
  A listing's status as a pill. The status is always written out in words;
  colour only reinforces it (design guide §6).
  """
  attr :listing, :map, required: true

  def status_badge(assigns) do
    ~H"""
    <span
      id={"listing-status-#{@listing.id}"}
      class={["badge badge-sm rounded-full whitespace-nowrap", status_class(@listing.status)]}
    >
      {status_label(@listing.status)}
    </span>
    """
  end

  defp status_class(:published), do: "badge-success"
  defp status_class(:pending), do: "badge-warning"
  defp status_class(:rejected), do: "badge-error"
  defp status_class(_status), do: "badge-ghost"
end
