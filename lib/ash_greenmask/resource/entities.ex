defmodule AshGreenmask.Resource.Transform do
  @moduledoc false

  defstruct [:attribute, :transformer, options: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          attribute: atom(),
          transformer: atom(),
          options: keyword()
        }
end

defmodule AshGreenmask.Resource.Keep do
  @moduledoc false

  defstruct [:attribute, :because, __spark_metadata__: nil]

  @type t :: %__MODULE__{attribute: atom(), because: String.t()}
end
