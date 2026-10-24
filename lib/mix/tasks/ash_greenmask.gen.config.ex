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

  Domains are resolved from `config :ash, :domains` unless `--domain` is
  given (repeatable).

  Refuse-by-default: a `sensitive?` attribute with neither `transform` nor
  `keep` fails generation with the resource, the attribute and the reason.
  """

  use Mix.Task

  @requirements ["app.config"]
  @default_out "greenmask.yml"

  @impl true
  def run(args) do
    {opts, _parsed, _invalid} =
      OptionParser.parse(args, strict: [check: :boolean, out: :string, domain: :keep])

    domains =
      case List.wrap(opts[:domain]) do
        [] ->
          Application.get_env(:ash, :domains) ||
            Mix.raise(
              "no domains configured: set config :ash, domains: [...] or pass --domain MyApp.Domain"
            )

        domains ->
          Enum.map(domains, &String.to_atom/1)
      end

    out = opts[:out] || @default_out

    case AshGreenmask.Generator.build(domains) do
      {:ok, document, residuals} ->
        rendered = AshGreenmask.Generator.render(document, residuals) |> IO.iodata_to_binary()

        if opts[:check] do
          check(out, rendered)
        else
          File.write!(out, rendered)
          Mix.shell().info("wrote #{out} (#{length(document.transform)} tables)")
          :ok
        end

      {:error, reasons} ->
        Enum.each(reasons, &Mix.shell().error(&1))

        Mix.raise(
          "greenmask config generation refused — #{length(reasons)} unresolved declaration(s)"
        )
    end
  end

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
