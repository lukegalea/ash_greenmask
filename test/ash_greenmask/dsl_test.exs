defmodule AshGreenmask.CatalogueTest do
  use ExUnit.Case, async: true

  alias AshGreenmask.Catalogue

  test "every entry maps to a CamelCase greenmask transformer name" do
    for {name, %{greenmask: greenmask}} <- Catalogue.all() do
      assert is_binary(greenmask)
      assert greenmask =~ ~r/^[A-Z][A-Za-z]+$/u, "#{name} -> #{greenmask}"
    end
  end

  test "type compatibility is closed, not advisory" do
    assert Catalogue.targets?(:masking, :string)
    assert Catalogue.targets?(:masking, :ci_string)
    refute Catalogue.targets?(:masking, :integer)

    assert Catalogue.targets?(:noise_int, :integer)
    refute Catalogue.targets?(:noise_int, :string)

    assert Catalogue.targets?(:noise_numeric, :decimal)

    assert Catalogue.targets?(:hash, :string)
    refute Catalogue.targets?(:hash, :uuid)

    # :any entries target everything
    assert Catalogue.targets?(:replace, :string)
    assert Catalogue.targets?(:replace, :uuid)
    assert Catalogue.targets?(:cmd, :decimal)

    # unknown names never match
    refute Catalogue.targets?(:definitely_not_a_transformer, :string)
  end
end

defmodule AshGreenmask.VerifierTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshGreenmask.Test.Support

  # Spark reports verifier errors from runtime-compiled modules as warnings,
  # so a refusal asserts on the logged DslError text, not a raise.
  defp assert_refusal(message) do
    assert message =~ "Spark.Error.DslError"
  end

  test "a well-formed block compiles" do
    defmodule Good do
      use Ash.Resource,
        domain: AshGreenmask.Test.Support.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshGreenmask.Resource]

      postgres do
        table "people"
        schema("public")
        repo(AshGreenmask.Test.Support.Repo)
      end

      attributes do
        uuid_primary_key :id
        attribute :email, :ci_string, sensitive?: true
        attribute :organization_id, :uuid
      end

      greenmask do
        transform(:email, :random_email)
        keep(:organization_id, because: "tenant key")
      end
    end

    assert [transform] = AshGreenmask.Info.transforms(Good)
    assert transform.transformer == :random_email
    assert [%{attribute: :organization_id, because: "tenant key"}] = AshGreenmask.Info.keeps(Good)
  end

  test "a transform on an attribute that does not exist is a compile-time refusal" do
    log =
      capture_io(:stderr, fn ->
        defmodule BadAttribute do
          use Ash.Resource,
            domain: nil,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshGreenmask.Resource]

          postgres do
            table "people"
            schema("public")
            repo(AshGreenmask.Test.Support.Repo)
          end

          attributes do
            uuid_primary_key :id
          end

          greenmask do
            transform(:email, :random_email)
          end
        end
      end)

    assert_refusal(log)
    assert log =~ "no such attribute"
  end

  test "a transformer outside the closed mapping is a compile-time refusal" do
    log =
      capture_io(:stderr, fn ->
        defmodule BadTransformer do
          use Ash.Resource,
            domain: nil,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshGreenmask.Resource]

          postgres do
            table "people"
            schema("public")
            repo(AshGreenmask.Test.Support.Repo)
          end

          attributes do
            uuid_primary_key :id
            attribute :count, :integer
          end

          greenmask do
            transform(:count, :noise)
          end
        end
      end)

    assert_refusal(log)
    assert log =~ "unknown transformer :noise"
    assert log =~ "the closed mapping"
  end

  test "a transformer that cannot target the attribute's type is a compile-time refusal" do
    log =
      capture_io(:stderr, fn ->
        defmodule BadType do
          use Ash.Resource,
            domain: nil,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshGreenmask.Resource]

          postgres do
            table "people"
            schema("public")
            repo(AshGreenmask.Test.Support.Repo)
          end

          attributes do
            uuid_primary_key :id
            attribute :count, :integer
          end

          greenmask do
            transform(:count, :masking)
          end
        end
      end)

    assert_refusal(log)
    assert log =~ "cannot target type"
  end

  test "keep without because is refused by the schema itself" do
    assert_raise Spark.Error.DslError, ~r/required :because option not found/, fn ->
      defmodule BadKeep do
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshGreenmask.Resource]

        postgres do
          table "people"
          schema("public")
          repo(AshGreenmask.Test.Support.Repo)
        end

        attributes do
          uuid_primary_key :id
          attribute :organization_id, :uuid
        end

        greenmask do
          keep(:organization_id)
        end
      end
    end
  end
end
