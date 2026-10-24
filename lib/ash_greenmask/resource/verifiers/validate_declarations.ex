defmodule AshGreenmask.Resource.Verifiers.ValidateDeclarations do
  @moduledoc """
  Compile-time structural validation of a `greenmask` block.

  The attribute must exist on the resource, the transformer must be in the
  closed catalogue, and the transformer must be able to target the
  attribute's declared Ash type. Failures name the resource, the attribute
  and the reason.
  """

  use Spark.Dsl.Verifier

  alias AshGreenmask.Catalogue
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    entities = Verifier.get_entities(dsl_state, [:greenmask])
    transforms = Enum.filter(entities, &is_struct(&1, AshGreenmask.Resource.Transform))
    resource = Verifier.get_persisted(dsl_state, :module)

    keeps = Enum.filter(entities, &is_struct(&1, AshGreenmask.Resource.Keep))

    attributes =
      resource
      |> Ash.Resource.Info.attributes()
      |> Map.new(&{&1.name, &1})

    transform_errors =
      Enum.flat_map(transforms, fn t ->
        cond do
          not Map.has_key?(attributes, t.attribute) ->
            ["#{inspect(resource)}: transform :#{t.attribute} — no such attribute"]

          is_nil(Catalogue.greenmask_name(t.transformer)) ->
            [
              "#{inspect(resource)}: transform :#{t.attribute} — unknown transformer :#{t.transformer}" <>
                hint(t.transformer)
            ]

          true ->
            attr = attributes[t.attribute]

            if Catalogue.targets?(t.transformer, attr.type) do
              []
            else
              [
                "#{inspect(resource)}: transform :#{t.attribute} — :#{t.transformer} cannot target type #{inspect(attr.type)}" <>
                  hint(t.transformer)
              ]
            end
        end
      end)

    keep_errors =
      Enum.flat_map(keeps, fn k ->
        if Map.has_key?(attributes, k.attribute) do
          []
        else
          ["#{inspect(resource)}: keep :#{k.attribute} — no such attribute"]
        end
      end)

    case transform_errors ++ keep_errors do
      [] -> :ok
      errors -> {:error, Spark.Error.DslError.exception(message: Enum.join(errors, "\n"))}
    end
  end

  defp hint(:random_email), do: " (did you mean :random_email? it targets string-ish types)"

  defp hint(transformer) when is_atom(transformer) do
    if Catalogue.greenmask_name(transformer) do
      " (see AshGreenmask.Catalogue for the types :#{transformer} may target)"
    else
      " (the closed mapping is in AshGreenmask.Catalogue — a name outside it is a refusal, not a pass-through)"
    end
  end
end
