defmodule AshGreenmask do
  @moduledoc """
  Pseudoanonymization config generated from Ash resource declarations.

  The knowledge of *what is sensitive* already lives in the resource model —
  `sensitive?: true` flags, attribute types, the table/column mapping
  `ash_postgres` maintains. This package stands between that model and
  [greenmask](https://github.com/GreenmaskIO/greenmask), a stateless
  transformer over `pg_dump`'s directory format: it derives greenmask's YAML
  from the declarations so the config can never drift from the model that
  owns the knowledge.

  One block on the resource:

      greenmask do
        transform :email, :random_email
        transform :phone, :masking, type: :tel
        transform :notes, :cmd, program: "notes-shaper", driver: :json

        keep :organization_id, because: "tenant key; a copy without it cannot be scoped"
      end

  and one generator:

      mix ash_greenmask.gen.config            # writes greenmask.yml (commit it)
      mix ash_greenmask.gen.config --check    # CI: fails when the YAML drifted

  ## Refuse-by-default

  Generation fails when a `sensitive?` attribute has neither a `transform`
  nor a `keep`, when a transformer name is not in the closed mapping
  (`AshGreenmask.Catalogue`), or when a transformer cannot target the
  attribute's type. The error names the resource, the attribute and the
  reason — ownership is never guessed.

  ## No runtime, no database objects

  The block compiles to Spark metadata and nothing else. No migration, no
  trigger, no code path in the running application. This is what keeps the
  extension cheap and swappable: the declarations carry no greenmask
  vocabulary a mapping table could not translate, and the emitter is one
  module.

  ## Determinism and the salt

  Referential continuity comes from greenmask's `Hash` engine (SHA-3 with
  `GREENMASK_GLOBAL_SALT`): the same input always produces the same output,
  and two columns transformed with identical hash parameters receive
  identical values. The salt is key material — env-injected at greenmask
  runtime, never in the repo, never in the generated config.

  The design decision and its commitments are recorded in
  [ADR 0032](https://github.com/lukegalea/ash_enterprise/blob/main/docs/adr/0032-anonymization-config-is-generated.md)
  and [the plan](https://github.com/lukegalea/ash_enterprise/blob/main/docs/plans/ash-greenmask.md).
  """

  @doc """
  Whether `resource` carries a `greenmask` block with any declaration.
  """
  @spec declared?(module()) :: boolean()
  def declared?(resource) do
    AshGreenmask.Info.transforms(resource) != [] or
      AshGreenmask.Info.keeps(resource) != []
  end
end
