<!--
SPDX-FileCopyrightText: 2026 Luke Galea

SPDX-License-Identifier: MIT
-->

# AshGreenmask

**Let production data leave production — without staying production data.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

An Ash extension that generates [greenmask](https://github.com/GreenmaskIO/greenmask)'s
config from what the resource model already knows: `sensitive?` flags, attribute
types, and the table/column mapping `ash_postgres` maintains. The knowledge of
*what to transform* lives in one place — the resource — and the YAML is a
derived artefact, committed and drift-gated.

The decision and design live, reviewed, in the reference application:
[ADR 0032](https://github.com/lukegalea/ash_enterprise/blob/main/docs/adr/0032-anonymization-config-is-generated.md)
and [the plan](https://github.com/lukegalea/ash_enterprise/blob/main/docs/plans/ash-greenmask.md).

## The DSL

```elixir
greenmask do
  # One transform per attribute that may leave production transformed.
  transform :email, :random_email
  transform :phone, :masking, type: :tel
  transform :notes, :cmd, program: "notes-shaper", driver: :json

  # The only way through unchanged, and it says why. The `because:` string
  # lands verbatim in the generated config's header — the residuals manifest.
  keep :organization_id, because: "tenant key; a copy without it cannot be scoped"
end
```

A table no value transform can make safe (a hash-chained ledger, a view) copies
its schema and none of its rows:

```elixir
greenmask do
  exclude_data because: "hash-chained ledger; a transformed row breaks the chain"
end
```

Compiles to Spark metadata only. No migration, no trigger, no runtime path in
the application.

## Generation and the drift gate

```console
$ mix ash_greenmask.gen.config             # writes greenmask.yml — commit it
$ mix ash_greenmask.gen.config --check     # CI: fails when the YAML drifted
```

Generation is **refuse-by-default**:

- a `sensitive?` attribute with neither `transform` nor `keep` is an error
  naming the resource, the attribute and the reason;
- with `strict?: true`, so is a postgres resource with a `sensitive?`
  attribute and no `greenmask` block at all (without it, such a resource is
  not looked at — the v0.1 behaviour, kept as the default for existing hosts);
- a transformer outside the closed mapping (`AshGreenmask.Catalogue`) is an
  error at compile time;
- a transformer that cannot target the attribute's type is an error at compile
  time.

## Configuration

```elixir
config :ash_greenmask,
  strict?: true,     # refuse a stored sensitive resource with no block (--strict)
  layout: :config,   # render the `dump` section greenmask reads (--layout config)
  default_schema: "public"  # where a resource with no `schema` in its postgres block lives
```

Domains come from `--domain`, else `config :ash, :domains`, else the host
app's own `config :my_app, ash_domains: [...]`.

The `:config` layout renders the `dump` section of a greenmask config: the
transformations, the `exclude_data` tables under
`pg_dump_options.exclude-table-data`, and `no-blobs` (large objects stay out
of the copy). The pipeline adds `common`, `storage` and the connection
(`DUMP_PG_DUMP_OPTIONS_DBNAME`), never this file. The default `:fragment`
layout is the v0.1 top-level `transformation` list, which greenmask does not
read on its own.

## Determinism

Referential continuity is greenmask's `Hash` engine: SHA-3 with
`GREENMASK_GLOBAL_SALT` — same input, same output, identical parameters on two
columns yield identical values. `Hash` targets `text` and `varchar` only; a
`uuid` key is made deterministic with `random_uuid` and `engine: "hash"`. The salt is key material, env-injected at dump
time, never in the repo and never in the generated config.

## Installation (git dependency while v0.x)

```elixir
def deps do
  [
    {:ash_greenmask, github: "lukegalea/ash_greenmask"}
  ]
end
```

## Status

v0.2 — `exclude_data`, strict mode, the `:config` layout, host-domain
resolution and `random_uuid`, all opt-in. v0.1 — the DSL, the closed transformer catalogue (verified against greenmask
v0.2.23's `list-transformers`), the generator and the `--check` drift gate.
Inheritance from a platform base resource and DSL-level subsetting are
deliberately out of v0.1 (declare per resource); see the plan's open questions
before growing the surface.
