defmodule Mix.Tasks.AshGreenmask.Gen.Config do
  @shortdoc "Generates greenmask.yml from the resource declarations"

  @moduledoc """
  Generates the greenmask config from the `greenmask` blocks on your
  resources. The generated file is committed — CI runs with `--check` to
  fail when it has drifted from the declarations, the same posture as
  `resource_snapshots/` and generated roadmap tables.

      mix ash_greenmask.gen.config                       # write greenmask.yml
      mix ash_greenmask.gen.config --check               # fail on drift
      mix ash_greenmask.gen.config --out config/gm.yml   # somewhere else

  Domains come from `--domain` (repeatable), else `config :ash, :domains`,
  else the host application's own `config :my_app, ash_domains: [...]`.

  Refuse-by-default: a `sensitive?` attribute with neither `transform` nor
  `keep` fails generation with the resource, the attribute and the reason.

  ## Configuration

      config :ash_greenmask,
        # Also refuse a stored resource with a sensitive attribute and no
        # `greenmask` block at all (`--strict` / `--no-strict` override).
        strict?: true,
        # Render the `dump` section greenmask reads, with the `exclude_data`
        # tables and `no-blobs` (`--layout config|fragment` overrides).
        layout: :config,
        # The schema of a resource whose postgres block names none.
        default_schema: "public"

  All three default to the v0.1 behaviour (`strict?: false`, `layout: :fragment`,
  no default schema).
  """

  use Mix.Task

  @requirements ["app.config"]
  @default_out "greenmask.yml"

  @impl true
  def run(args) do
    Mix.Task.run("loadpaths", [])

    {opts, _parsed, _invalid} =
      OptionParser.parse(args,
        strict: [check: :boolean, out: :string, domain: :keep, strict: :boolean, layout: :string]
      )

    domains = domains(opts)
    out = opts[:out] || @default_out

    build_opts = [
      strict?: Keyword.get(opts, :strict, Application.get_env(:ash_greenmask, :strict?, false)),
      layout: layout(opts[:layout] || Application.get_env(:ash_greenmask, :layout, :fragment)),
      default_schema: Application.get_env(:ash_greenmask, :default_schema)
    ]

    case AshGreenmask.Generator.build(domains, build_opts) do
      {:ok, document, residuals} ->
        rendered = AshGreenmask.Generator.render(document, residuals) |> IO.iodata_to_binary()

        if opts[:check] do
          check(out, rendered)
        else
          File.write!(out, rendered)
          tables = length(AshGreenmask.Generator.tables(document))
          Mix.shell().info("wrote #{out} (#{tables} tables)")
          :ok
        end

      {:error, reasons} ->
        Enum.each(reasons, &Mix.shell().error(&1))

        Mix.raise(
          "greenmask config generation refused — #{length(reasons)} unresolved declaration(s)"
        )
    end
  end

  @doc false
  def domains(opts) do
    case List.wrap(opts[:domain]) do
      [] ->
        Application.get_env(:ash, :domains) || host_domains() ||
          Mix.raise(
            "no domains configured: set config :ash, domains: [...], config :#{Mix.Project.config()[:app]}, ash_domains: [...], or pass --domain MyApp.Domain"
          )

      domains ->
        # Module names given on the command line; Module.concat does not mint
        # a bare atom from arbitrary input the way String.to_atom/1 would.
        Enum.map(domains, &Module.concat([&1]))
    end
  end

  defp host_domains do
    case Mix.Project.config()[:app] do
      nil -> nil
      app -> Application.get_env(app, :ash_domains)
    end
  end

  defp layout(layout) when layout in [:fragment, :config], do: layout
  defp layout("fragment"), do: :fragment
  defp layout("config"), do: :config

  defp layout(other),
    do: Mix.raise("unknown layout #{inspect(other)}: expected fragment or config")

  defp check(out, rendered) do
    case File.read(out) do
      {:ok, existing} when existing == rendered ->
        Mix.shell().info("#{out} matches the resource declarations")
        :ok

      {:ok, _existing} ->
        Mix.shell().error("#{out} has drifted from the resource declarations.")
        Mix.shell().error("regenerate with `mix ash_greenmask.gen.config` and commit the result.")
        Mix.raise("greenmask config drift")

      {:error, _} ->
        Mix.shell().error(
          "#{out} does not exist; generate it with `mix ash_greenmask.gen.config` and commit it."
        )

        Mix.raise("greenmask config missing")
    end
  end
end
