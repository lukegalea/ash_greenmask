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
end
