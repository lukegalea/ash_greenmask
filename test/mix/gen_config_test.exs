defmodule Mix.Tasks.AshGreenmask.Gen.ConfigTest do
  # Mutates application env.
  use ExUnit.Case, async: false

  alias Mix.Tasks.AshGreenmask.Gen.Config

  setup do
    on_exit(fn -> Application.delete_env(:ash_greenmask, :ash_domains) end)
  end

  test "with no domain configured anywhere, the task refuses and names every place it looked" do
    assert_raise Mix.Error, ~r/config :ash_greenmask, ash_domains/, fn -> Config.domains([]) end
  end

  test "domains resolve from the host app's :ash_domains" do
    Application.put_env(:ash_greenmask, :ash_domains, [AshGreenmask.Test.Support.Domain])
    assert Config.domains([]) == [AshGreenmask.Test.Support.Domain]
  end

  test "--domain names a module" do
    assert Config.domains(domain: "AshGreenmask.Test.Support.Domain") == [
             AshGreenmask.Test.Support.Domain
           ]
  end
end
