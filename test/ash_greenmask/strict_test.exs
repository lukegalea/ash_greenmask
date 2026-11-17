defmodule AshGreenmask.StrictTest do
  use ExUnit.Case, async: true

  alias AshGreenmask.Generator
  alias AshGreenmask.Test.Support

  describe "strict mode" do
    test "a resource with a sensitive attribute and no greenmask block is a generation error" do
      assert {:error, [reason]} = Generator.build([Support.StrictDomain], strict?: true)

      assert reason =~ "#{inspect(Support.Undeclared)}: :email, :token are sensitive"
      assert reason =~ "has no `greenmask` block"
      assert reason =~ "never a pass-through"
    end

    test "without strict mode the same resource is not looked at, as in v0.1" do
      assert {:ok, document, _residuals} = Generator.build([Support.StrictDomain])
      refute Enum.any?(Generator.tables(document), &(&1.name == "undeclared"))
    end

    test "an excluded table, a resource outside postgres and a resource with nothing sensitive need no block" do
      assert {:ok, _document, residuals} = Generator.build([Support.CoveredDomain], strict?: true)

      assert residuals == [
               "#{inspect(Support.Ledger)}: rows not copied (exclude_data) — hash-chained; a transformed row breaks the chain"
             ]
    end
  end

  describe "the config layout" do
    test "two resources over one table are refused" do
      assert {:error, [reason]} = Generator.build([Support.DuplicateDomain], layout: :config)
      assert reason =~ "audit.ledger is declared by more than one resource"
    end

    test "renders the dump section, with excluded tables and no large objects" do
      assert {:ok, document, residuals} =
               Generator.build([Support.CoveredDomain, Support.Domain], layout: :config)

      assert %{
               "dump" => %{
                 "pg_dump_options" => %{
                   "exclude-table-data" => ["audit.ledger"],
                   "no-blobs" => true
                 },
                 "transformation" => [%{"schema" => "public", "name" => "people"}]
               }
             } = document

      rendered = document |> Generator.render(residuals) |> IO.iodata_to_binary()
      assert rendered == document |> Generator.render(residuals) |> IO.iodata_to_binary()

      assert rendered =~ """
             dump:
               pg_dump_options:
                 exclude-table-data:
                   - "audit.ledger"
                 no-blobs: true
               transformation:
                 - name: "people"
                   schema: "public"
                   transformers:
                     - name: "RandomEmail"
             """

      assert rendered =~ "rows not copied (exclude_data) — hash-chained"
      assert rendered =~ "this config sets `no-blobs`"
      assert rendered =~ "This is the `dump` section of a greenmask config."
      assert rendered =~ "executes an arbitrary command at dump time"
    end

    test "the rendered config parses as YAML with the same shape" do
      assert {:ok, document, residuals} =
               Generator.build([Support.CoveredDomain], layout: :config)

      rendered = document |> Generator.render(residuals) |> IO.iodata_to_binary()

      assert {:ok,
              %{
                "dump" => %{
                  "pg_dump_options" => %{"exclude-table-data" => ["audit.ledger"]},
                  "transformation" => []
                }
              }} = YamlElixir.read_from_string(rendered)
    end
  end
end
