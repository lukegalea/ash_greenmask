<!--
SPDX-FileCopyrightText: 2026 Luke Galea

SPDX-License-Identifier: MIT
-->

# AshGreenmask

**Let production data leave production — without staying production data.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

> **Nothing here is built.** This repository exists to hold the extension when it
> is written. The decision and the design live, reviewed, in the reference
> application:
> [ADR 0032](https://github.com/lukegalea/ash_enterprise/blob/main/docs/adr/0032-anonymization-config-is-generated.md)
> and [the plan](https://github.com/lukegalea/ash_enterprise/blob/main/docs/plans/ash-greenmask.md).

## The situation

Every environment that is not production runs one of two things, and both fail.

**Seed data** is safe and useless at the only moments that matter. A hand-shaped
demo tenant cannot exercise an authorization model at enterprise shape, cannot
surface the query that returns forty thousand rows, and cannot reproduce the bug
that only appears with real dirt under its fingernails — real data is dirty in
ways no seeder imagines, and the dirt is the payload.

**Production data** is representative and unacceptable. A tenant's records on a
developer laptop, in a CI runner, or on a staging instance with debug logging
enabled is a breach by definition, and under GDPR a new processing purpose on
top. The gap between the two failures is not bridged by discipline: developers
who cannot get representative data safely get it unsafely, eventually, at 2am,
with a ticket open.

What is needed is a third thing: a copy of production that has stopped being
production data — same shape, same dirt, same row counts, no persons.

## The shape

[Greenmask](https://github.com/GreenmaskIO/greenmask) transforms a `pg_dump` in
flight — stateless, declarative, Apache-2.0 — and it has **no opinion about what
is sensitive**. It transforms exactly what its config names and nothing else.
Ash already knows what is sensitive: attributes carry `sensitive?`, types are
declared, and `ash_postgres` maintains the resource-to-table mapping.

AshGreenmask stands between the two:

```elixir
greenmask do
  transform :email, :random_email
  transform :id, :hash, apply_for_references: true

  # The only way through unchanged, and it says why.
  keep :organization_id, because: "tenant key; a copy without it cannot be scoped"
end
```

- `mix ash_greenmask.gen.config` emits greenmask's YAML from those declarations
  plus what the model already knows. The config is a derived artifact, gated in
  CI beside the resource snapshots and the roadmap tables — derived artifacts
  that *can* drift from their source eventually do.
- **Refuse-by-default.** A `sensitive?` attribute with no declared transform and
  no explicit `keep` is a generation error, not a passthrough. The column
  someone forgets is the column that matters.
- **Referential continuity** from greenmask's hash engine with an env-injected
  salt: the same person yields the same pseudonym, foreign keys still resolve,
  and separate destination environments cannot be joined to re-identify across
  them, because each carries its own salt.
- **No database objects, nothing running in the application.** The block
  compiles to metadata; the artifact is a config consumed outside the boundary.

## What it refuses

- A hand-maintained config, which is a second copy of knowledge the model
  already owns, and which drifts permissively.
- greenmask's full transformer catalogue, in favour of a closed, curated mapping
  that keeps an engine swap measurable rather than speculative.
- The word "anonymized". What this produces is *pseudo*anonymized data — it
  names no person without the salt — and the salt's custody is what the claim
  rests on.

## Documentation

- [ADR 0032 — Anonymization config is generated from the resource
  declarations](https://github.com/lukegalea/ash_enterprise/blob/main/docs/adr/0032-anonymization-config-is-generated.md)
- [The plan](https://github.com/lukegalea/ash_enterprise/blob/main/docs/plans/ash-greenmask.md)
  in the reference application
- [Greenmask documentation](https://docs.greenmask.io/) — the transformation
  engine

## License

MIT.
