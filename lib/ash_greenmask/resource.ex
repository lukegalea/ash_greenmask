defmodule AshGreenmask.Resource do
  @moduledoc """
  The `greenmask` DSL block: how each attribute of this resource may leave
  production.

  Every declaration is validated at compile time — the attribute must exist,
  the transformer must be in `AshGreenmask.Catalogue`, and the transformer
  must be able to target the attribute's type. The sensitive-coverage
  invariant (every `sensitive?` attribute has a `transform` or a `keep`) is
  enforced at generation time, where the whole picture is visible.
  """

  @transform %Spark.Dsl.Entity{
    name: :transform,
    args: [:attribute, :transformer, {:optional, :options}],
    target: AshGreenmask.Resource.Transform,
    schema: [
      attribute: [type: :atom, required: true, doc: "The Ash attribute (never the column)."],
      transformer: [type: :atom, required: true, doc: "A name from `AshGreenmask.Catalogue`."],
      options: [
        type: :keyword_list,
        default: [],
        doc: "Greenmask transformer parameters, passed through (column is derived)."
      ]
    ]
    # One transform per attribute that may leave production transformed:
    #     transform :email, :random_email
    #     transform :phone, :masking, type: :tel
  }

  @keep %Spark.Dsl.Entity{
    name: :keep,
    args: [:attribute],
    target: AshGreenmask.Resource.Keep,
    schema: [
      attribute: [type: :atom, required: true, doc: "The Ash attribute kept unchanged."],
      because: [
        type: :string,
        required: true,
        doc: "Why this may pass through. Lands verbatim in the generated config's header."
      ]
    ]
    # The only way through unchanged, and it says why:
    #     keep :organization_id, because: "tenant key; a copy without it cannot be scoped"
  }

  @exclude_data %Spark.Dsl.Entity{
    name: :exclude_data,
    args: [],
    target: AshGreenmask.Resource.ExcludeData,
    schema: [
      because: [
        type: :string,
        required: true,
        doc:
          "Why this table's rows stay out of the copy. Lands verbatim in the generated config's header."
      ]
    ]
    # The table's schema is copied and its rows are not, for a table no
    # value transform can make safe (a hash-chained ledger, a view):
    #     exclude_data because: "hash-chained ledger; a transformed row breaks the chain"
  }

  @greenmask %Spark.Dsl.Section{
    name: :greenmask,
    entities: [@transform, @keep, @exclude_data],
    describe: """
    Declares how this resource's attributes may leave production. Compiles
    to metadata only — no migration, no runtime. The generated greenmask
    config (`mix ash_greenmask.gen.config`) is the derived artefact.
    """,
    examples: [
      """
      greenmask do
        transform :email, :random_email
        keep :organization_id, because: "tenant key; a copy without it cannot be scoped"
      end
      """
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@greenmask],
    verifiers: [AshGreenmask.Resource.Verifiers.ValidateDeclarations]
end
