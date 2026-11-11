# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Jairojobs.Repo.insert!(%Jairojobs.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# spec 002 — REQ-002-5: the launch regions (Davao City, Cebu, Metro Manila).
# Idempotent: only inserts what is missing.
Jairojobs.Regions.seed_launch_regions()
