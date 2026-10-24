defmodule AshGreenmask.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ash_greenmask,
      version: @version,
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      docs: docs(),
      source_url: "https://github.com/lukegalea/ash_greenmask",
      homepage_url: "https://github.com/lukegalea/ash_greenmask"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application, do: []

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:yaml_elixir, "~> 2.11"},
      {:simple_sat, "~> 0.1", only: [:dev, :test]},
      {:ex_doc, "~> 0.37", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/lukegalea/ash_greenmask",
        "ADR 0032 (the decision)" =>
          "https://github.com/lukegalea/ash_enterprise/blob/main/docs/adr/0032-anonymization-config-is-generated.md",
        "Design plan" =>
          "https://github.com/lukegalea/ash_enterprise/blob/main/docs/plans/ash-greenmask.md"
      }
    ]
  end

  defp description do
    "Pseudoanonymization config generated from Ash resource declarations — the greenmask YAML is derived, never hand-maintained."
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
