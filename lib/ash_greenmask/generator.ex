defmodule AshGreenmask.Generator do
  @moduledoc """
  Derives the greenmask YAML from the resource declarations.

  Refuse-by-default lives here, where the whole picture is visible: a
  `sensitive?` attribute with neither a `transform` nor a `keep` is a
  generation error naming the resource, the attribute and the reason —
  never a silent pass-through. What passes through deliberately is stated
  in the header (the residuals manifest), because an artefact that hides
  its own gaps is worse than one that declares them.

  The output is deterministic: same declarations, same bytes. That is what
  makes `--check` a meaningful drift gate.
  """

  alias AshGreenmask.Catalogue
  alias AshGreenmask.Info

  @large_objects_note """
  Large objects pass through untransformed — greenmask's transformers target
  table data. The dump excludes them by default; keeping them is a pipeline
  option that also carries this warning.
  """

  @config_large_objects_note """
  Large objects are not copied: this config sets `no-blobs`, so their content
  stays out of the dump and only their metadata (oid, owner) is restored.
  greenmask's transformers target table data and could not transform them.
  """

  @config_layout_note """
  This is the `dump` section of a greenmask config. The pipeline supplies the
  rest — `common`, `storage` and the connection (for example
  DUMP_PG_DUMP_OPTIONS_DBNAME) — and never writes them here.
  """

  @typedoc """
  - `strict?` — refuse a postgres resource with a `sensitive?` attribute and
    no `greenmask` block at all (default `false`; without it such a resource
    is not looked at).
  - `layout` — `:fragment` (default) renders a top-level `transformation`
    list; `:config` renders the `dump` section greenmask reads, with the
    `exclude_data` tables in `pg_dump_options.exclude-table-data` and
    `no-blobs` set.
  """
  @type option :: {:strict?, boolean()} | {:layout, :fragment | :config}

  @doc """
  Builds the greenmask config document (a map) for `domains`.

  Returns `{:ok, document, residuals}` or `{:error, reasons}` — reasons are
  strings, one per refusal. See `t:option/0` for `opts`.
  """
  @spec build([module()], [option()]) ::
          {:ok, map(), [String.t()]} | {:error, [String.t()]}
  def build(domains, opts \\ []) when is_list(domains) do
    Enum.each(domains, &Code.ensure_compiled!/1)
    layout = Keyword.get(opts, :layout, :fragment)

    all =
      domains
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()

    resources = Enum.filter(all, &AshGreenmask.declared?/1)
    {excluded, copied} = Enum.split_with(resources, &Info.exclude_data/1)

    undeclared = if Keyword.get(opts, :strict?, false), do: undeclared(all), else: []

    with {:ok, tables} <- collect(undeclared, table_entries(copied)),
         {:ok, excluded_tables} <- excluded_tables(excluded),
         :ok <- unique_tables(layout, tables, excluded_tables) do
      {:ok, document(layout, tables, excluded_tables), residuals(resources)}
    end
  end

  @doc "The table entries of a built document, in either layout."
  @spec tables(map()) :: [map()]
  def tables(%{"dump" => %{"transformation" => tables}}), do: tables
  def tables(%{transformation: tables}), do: tables

  defp document(:fragment, tables, _excluded), do: %{transformation: tables}

  defp document(:config, tables, excluded) do
    options =
      case excluded do
        [] -> %{"no-blobs" => true}
        excluded -> %{"exclude-table-data" => excluded, "no-blobs" => true}
      end

    # String keys render in byte order on every build; atom keys in a small
    # map iterate in atom-creation order, which a build does not fix.
    tables =
      Enum.map(tables, fn table ->
        %{
          "schema" => table.schema,
          "name" => table.name,
          "transformers" =>
            Enum.map(table.transformers, &%{"name" => &1.name, "params" => &1.params})
        }
      end)

    %{"dump" => %{"pg_dump_options" => options, "transformation" => tables}}
  end

  # Strict mode: a stored resource that carries a sensitive attribute and no
  # block at all is the gap a declared-only scan cannot see.
  defp undeclared(resources) do
    for resource <- resources,
        Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer,
        not AshGreenmask.declared?(resource),
        sensitive = sensitive_names(resource),
        sensitive != [] do
      "#{inspect(resource)}: #{Enum.map_join(sensitive, ", ", &":#{&1}")} " <>
        "#{if length(sensitive) == 1, do: "is", else: "are"} sensitive and the resource has no `greenmask` block" <>
        " — in strict mode a sensitive attribute with no position is a generation error, never a pass-through." <>
        " Transform or keep each one, or exclude the table's rows with `exclude_data`."
    end
  end

  defp sensitive_names(resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(& &1.sensitive?)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp collect([], result), do: result
  defp collect(errors, {:ok, _}), do: {:error, errors}
  defp collect(errors, {:error, more}), do: {:error, errors ++ more}

  defp excluded_tables(resources) do
    {names, errors} =
      Enum.reduce(resources, {[], []}, fn resource, {names, errors} ->
        with {:ok, schema} <- schema(resource),
             {:ok, name} <- table_name(resource) do
          {["#{schema}.#{name}" | names], errors}
        else
          {:error, reason} -> {names, [reason | errors]}
        end
      end)

    case errors do
      [] -> {:ok, names |> Enum.uniq() |> Enum.sort()}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # In a config greenmask reads, one table is declared once: two resources
  # over the same table would leave which transformers apply to the order of
  # the list.
  defp unique_tables(:fragment, _tables, _excluded), do: :ok

  defp unique_tables(:config, tables, excluded) do
    names = Enum.map(tables, &"#{&1.schema}.#{&1.name}") ++ excluded

    case names -- Enum.uniq(names) do
      [] ->
        :ok

      duplicates ->
        {:error,
         Enum.map(Enum.uniq(duplicates), fn name ->
           "#{name} is declared by more than one resource — declare its `greenmask` block on one of them"
         end)}
    end
  end

  defp table_entries(resources) do
    {tables, errors} =
      Enum.reduce(resources, {[], []}, fn resource, {tables, errors} ->
        case table(resource) do
          {:ok, table} -> {[table | tables], errors}
          {:error, reasons} -> {tables, Enum.reverse(reasons) ++ errors}
        end
      end)

    case errors do
      [] -> {:ok, Enum.reverse(tables)}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp table(resource) do
    with {:ok, schema} <- schema(resource),
         {:ok, name} <- table_name(resource),
         {:ok, transformers} <- transformers(resource) do
      {:ok, %{schema: schema, name: name, transformers: transformers}}
    end
  end

  defp schema(resource) do
    case AshPostgres.DataLayer.Info.schema(resource) do
      nil ->
        {:error,
         "#{inspect(resource)} declares a greenmask block but has no postgres schema — the generator refuses to guess where it lives"}

      schema ->
        {:ok, schema}
    end
  end

  defp table_name(resource) do
    case AshPostgres.DataLayer.Info.table(resource) do
      nil ->
        {:error,
         "#{inspect(resource)} declares a greenmask block but has no postgres table — the generator refuses to guess where it lives"}

      table ->
        {:ok, table}
    end
  end

  defp transformers(resource) do
    attributes =
      resource
      |> Ash.Resource.Info.attributes()
      |> Map.new(&{&1.name, &1})

    uncovered =
      attributes
      |> Enum.filter(fn {_name, attr} -> attr.sensitive? end)
      |> Enum.reject(fn {name, _attr} -> covered?(resource, name) end)
      |> Enum.map(fn {name, _attr} ->
        "#{inspect(resource)}: :#{name} is sensitive and has neither `transform` nor `keep`" <>
          " — a sensitive attribute with no position is a generation error, never a pass-through." <>
          " Transform it, or keep it with a `because:` that says why."
      end)

    transformers =
      Enum.map(Info.transforms(resource), fn t ->
        attr = Map.fetch!(attributes, t.attribute)
        column = attr.source || attr.name

        %{
          name: Catalogue.greenmask_name(t.transformer),
          params:
            Map.new(Enum.concat([[column: to_string(column)], t.options]), fn {k, v} ->
              {to_string(k), v}
            end)
        }
      end)

    case uncovered do
      [] -> {:ok, transformers}
      uncovered -> {:error, uncovered}
    end
  end

  defp covered?(resource, name) do
    Enum.any?(Info.transforms(resource), &(&1.attribute == name)) or
      Enum.any?(Info.keeps(resource), &(&1.attribute == name))
  end

  defp residuals(resources) do
    Enum.flat_map(resources, fn resource ->
      case Info.exclude_data(resource) do
        nil -> kept_residuals(resource)
        %{because: because} ->
          ["#{inspect(resource)}: rows not copied (exclude_data) — #{because}"]
      end
    end)
  end

  # A small atom-keyed map iterates in atom-creation order, which differs between
  # builds; sorting by name keeps the manifest the same for the same declarations.
  defp kept_residuals(resource) do
    resource
    |> Info.residual_because()
    |> Enum.sort_by(fn {attribute, _because} -> Atom.to_string(attribute) end)
    |> Enum.map(fn {attribute, because} ->
      "#{inspect(resource)}: :#{attribute} — #{because}"
    end)
  end

  @doc """
  Renders the document + residuals as the committed YAML file: a header
  comment block (generated, residuals, `cmd` warnings, large-objects note)
  followed by the config body. Deterministic for identical inputs.
  """
  def render(document, residuals) do
    config? = Map.has_key?(document, "dump")

    cmd_warnings =
      document
      |> cmd_transformers()
      |> Enum.map(
        &"#{&1} executes an arbitrary command at dump time. That is the escape hatch, and this header says so on every use."
      )

    header =
      [
        "This file is generated by `mix ash_greenmask.gen.config`. DO NOT EDIT."
      ] ++
        [
          "Regenerate after changing any `greenmask` block; CI fails on drift (`--check`)."
        ] ++
        wrap("Residuals — what passes through unchanged, and why:", residuals, "  none") ++
        wrap("cmd transformers in use:", cmd_warnings, "  none") ++
        [
          if(config?, do: @config_large_objects_note, else: @large_objects_note)
        ] ++
        if(config?, do: [@config_layout_note], else: []) ++
        [
          "The salt never lives here: greenmask reads GREENMASK_GLOBAL_SALT from the environment at dump time."
        ]

    header
    |> Enum.flat_map(&String.split(&1, "\n"))
    |> Enum.map(&"# #{&1}\n")
    |> then(&(&1 ++ to_yaml(document, 0)))
  end

  defp wrap(_title, [], _empty), do: []

  defp wrap(title, lines, _empty) do
    [title | Enum.map(lines, &"  - #{&1}")]
  end

  defp cmd_transformers(document) do
    document
    |> tables()
    |> Enum.flat_map(&field(&1, :transformers))
    |> Enum.filter(&(field(&1, :name) == "Cmd"))
    |> Enum.map(&"Cmd on #{inspect(&1)}")
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  # A deliberately small YAML writer for this fixed document shape. The
  # generated file must be byte-stable, so everything renders in
  # declaration order and maps are never hashed. A sequence item renders
  # its FIRST key inline after the dash and the rest aligned under it —
  # the shape YAML requires of sequence-of-mapping items.
  defp to_yaml(%{} = map, indent) do
    map
    |> Enum.map_join("", fn {key, value} -> render_pair(key, value, indent) end)
  end

  defp to_yaml(list, indent) when is_list(list) do
    Enum.map_join(list, "", &list_item(&1, indent))
  end

  defp to_yaml(scalar, _indent), do: "#{scalar(scalar)}\n"

  defp list_item(%{} = map, indent) do
    case Enum.to_list(map) do
      [] ->
        pad(indent, "- {}\n")

      [{key, value} | rest] ->
        # The dash replaces the first pair's pad: "- name: x" with the rest
        # aligned under `name`, exactly where render_pair(indent + 1) puts them.
        dash = pad(indent, "- ")

        dash <>
          (render_pair(key, value, indent + 1) |> String.trim_leading(" ")) <>
          Enum.map_join(rest, "", fn {k, v} -> render_pair(k, v, indent + 1) end)
    end
  end

  defp list_item(other, indent) do
    pad(indent, "- ") <> to_yaml(other, indent + 1)
  end

  defp render_pair(key, %{} = nested, indent) do
    pad(indent, "#{key}:\n") <> to_yaml(nested, indent + 1)
  end

  defp render_pair(key, list, indent) when is_list(list) do
    if list == [] do
      pad(indent, "#{key}: []\n")
    else
      pad(indent, "#{key}:\n") <> to_yaml(list, indent + 1)
    end
  end

  defp render_pair(key, value, indent) do
    pad(indent, "#{key}: #{scalar(value)}\n")
  end

  defp pad(indent, suffix), do: String.duplicate("  ", indent) <> suffix

  defp scalar(value) when is_nil(value), do: "null"
  defp scalar(value) when is_binary(value), do: inspect(value)
  defp scalar(value) when is_atom(value), do: to_string(value)

  defp scalar(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: to_string(value)

  defp scalar(value), do: inspect(value)
end
