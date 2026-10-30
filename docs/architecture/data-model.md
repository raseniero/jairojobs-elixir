# Data Model

**Last updated:** 2026-10-29 (bootstrap — no tables yet)

Living document. Update the ERD and table list when a spec adds or changes schemas.
The authoritative source is `priv/repo/migrations/` + the `Ecto.Schema` modules;
this page is the readable summary.

## Conventions

- Primary keys: _TBD_ (bigint default vs UUID — decide via ADR before first domain table)
- Timestamps: `inserted_at` / `updated_at` (`utc_datetime_usec`)
- Soft deletes: not used unless a spec requires it
- Naming: snake_case, plural table names, singular schema modules

## ERD

```mermaid
erDiagram
    %% no entities yet
```

## Tables

| Table | Schema module | Context | Introduced by spec |
|---|---|---|---|
| _none yet_ | | | |
