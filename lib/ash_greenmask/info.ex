defmodule AshGreenmask.Info do
  @moduledoc """
  Introspection over a resource's `greenmask` block.
  """

  @spec transforms(module()) :: [AshGreenmask.Resource.Transform.t()]
  def transforms(resource) do
    resource
    |> Spark.Dsl.Extension.get_entities([:greenmask])
    |> Enum.filter(&is_struct(&1, AshGreenmask.Resource.Transform))
  end

  @spec keeps(module()) :: [AshGreenmask.Resource.Keep.t()]
  def keeps(resource) do
    resource
    |> Spark.Dsl.Extension.get_entities([:greenmask])
    |> Enum.filter(&is_struct(&1, AshGreenmask.Resource.Keep))
  end

  @doc """
  The kept attributes as a map of `attribute => because`, for the residuals
  manifest the generator emits.
  """
  @spec residual_because(module()) :: %{atom() => String.t()}
  def residual_because(resource) do
    resource |> keeps() |> Map.new(&{&1.attribute, &1.because})
  end
end
