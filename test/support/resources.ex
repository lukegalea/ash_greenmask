defmodule AshGreenmask.Test.Support do
  @moduledoc false

  defmodule Repo do
    @moduledoc false
    use AshPostgres.Repo,
      otp_app: :ash_greenmask,
      warn_on_missing_ash_functions?: false

    def installed_extensions, do: []
    def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Person
    end
  end

  defmodule KeptDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Kept
    end
  end

  defmodule UncoveredDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Uncovered
    end
  end

  defmodule Person do
    @moduledoc false
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
      attribute :phone, :string, sensitive?: true
      attribute :secret_note, :string, sensitive?: true
      attribute :full_name, :string
      attribute :organization_id, :uuid
    end

    greenmask do
      transform(:email, :random_email)
      transform(:phone, :masking, type: :tel)
      transform(:secret_note, :cmd, program: "note-shaper", driver: :json)
      transform(:full_name, :hash, function: "sha3-512")
      keep(:organization_id, because: "tenant key; a copy without it cannot be scoped")
    end
  end

  # The keeps are declared against name order, on atoms nothing else in the VM uses,
  # so the atoms are created in the opposite of name order.
  defmodule Kept do
    @moduledoc false
    use Ash.Resource,
      domain: AshGreenmask.Test.Support.KeptDomain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshGreenmask.Resource]

    postgres do
      table "kept"
      schema("public")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :zz_greenmask_last, :string, sensitive?: true
      attribute :mm_greenmask_middle, :string, sensitive?: true
      attribute :aa_greenmask_first, :string, sensitive?: true
    end

    greenmask do
      keep(:zz_greenmask_last, because: "z")
      keep(:mm_greenmask_middle, because: "m")
      keep(:aa_greenmask_first, because: "a")
    end
  end

  defmodule Uncovered do
    @moduledoc false
    use Ash.Resource,
      domain: AshGreenmask.Test.Support.UncoveredDomain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshGreenmask.Resource]

    postgres do
      table "uncovered"
      schema("public")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :ci_string, sensitive?: true
    end

    greenmask do
      keep(:id, because: "the key")
    end
  end

  defmodule StrictDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Undeclared
      resource AshGreenmask.Test.Support.Ledger
      resource AshGreenmask.Test.Support.InMemory
      resource AshGreenmask.Test.Support.Plain
    end
  end

  defmodule CoveredDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Ledger
      resource AshGreenmask.Test.Support.InMemory
      resource AshGreenmask.Test.Support.Plain
    end
  end

  defmodule DuplicateDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.Ledger
      resource AshGreenmask.Test.Support.PersonAgain
    end
  end

  # Stored, sensitive, and no greenmask block at all: the gap strict mode closes.
  defmodule Undeclared do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "undeclared"
      schema("public")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :token, :string, sensitive?: true
      attribute :email, :string, sensitive?: true
    end
  end

  defmodule Ledger do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshGreenmask.Resource]

    postgres do
      table "ledger"
      schema("audit")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :data, :map, sensitive?: true
    end

    greenmask do
      exclude_data(because: "hash-chained; a transformed row breaks the chain")
    end
  end

  # Not stored in postgres: not in any dump, so strict mode does not ask.
  defmodule InMemory do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :secret, :string, sensitive?: true
    end
  end

  # Stored, nothing sensitive, no block: nothing to declare.
  defmodule Plain do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: AshPostgres.DataLayer

    postgres do
      table "plain"
      schema("public")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string
    end
  end

  defmodule PersonAgain do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshGreenmask.Resource]

    # The same table the ledger excludes, declared a second time.
    postgres do
      table "ledger"
      schema("audit")
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :ci_string, sensitive?: true
    end

    greenmask do
      transform(:email, :hash)
    end
  end

  defmodule NoSchemaDomain do
    @moduledoc false
    use Ash.Domain

    resources do
      resource AshGreenmask.Test.Support.NoSchema
    end
  end

  # A postgres block that names no schema: the repo's default.
  defmodule NoSchema do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshGreenmask.Resource]

    postgres do
      table "no_schema"
      repo(AshGreenmask.Test.Support.Repo)
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, sensitive?: true
    end

    greenmask do
      transform(:email, :random_email)
    end
  end
end
