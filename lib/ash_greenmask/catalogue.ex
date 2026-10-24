defmodule AshGreenmask.Catalogue do
  @moduledoc """
  The closed, curated mapping from DSL transformer names to greenmask
  transformers — not greenmask's full catalogue of 51.

  The mapping is the compatibility surface that makes an engine swap
  measurable: a surface of 51 entries is a surface nobody audits. Types are
  part of the mapping — each entry declares the Ash types it can target, and
  a mismatch is a compile-time refusal, not a `greenmask validate` discovery.

  Greenmask transformer facts verified against the pinned binary (v0.2.23,
  `greenmask list-transformers` / `show-transformer`), 2026-10-24. The
  `Hash` engine's parameters: `salt` (env `GREENMASK_GLOBAL_SALT`),
  `function` (sha1, sha256, sha512, sha3-224, sha3-254, sha3-384, sha3-512,
  md5; default sha3-254), `max_length`.
  """

  @stringish [:string, :ci_string, :atom]
  @any :any

  @transformers %{
    masking: %{
      greenmask: "Masking",
      types: @stringish,
      doc:
        "Mask a value using one of greenmask's logical types (type: default, password, name, addr, email, mobile, tel, id, credit_card, url, postcode)."
    },
    replace: %{
      greenmask: "Replace",
      types: @any,
      doc: "Replace the column value with a fixed value."
    },
    regexp_replace: %{
      greenmask: "RegexpReplace",
      types: @stringish,
      doc: "Replace via regular expression."
    },
    set_null: %{greenmask: "SetNull", types: @any, doc: "Set NULL."},
    noise_int: %{greenmask: "NoiseInt", types: [:integer], doc: "Random noise within thresholds."},
    noise_float: %{
      greenmask: "NoiseFloat",
      types: [:float],
      doc: "Random noise within thresholds."
    },
    noise_numeric: %{
      greenmask: "NoiseNumeric",
      types: [:decimal],
      doc: "Random noise within thresholds."
    },
    noise_date: %{
      greenmask: "NoiseDate",
      types: [:date, :naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec],
      doc: "Shift a temporal value by a random interval."
    },
    random_email: %{greenmask: "RandomEmail", types: @stringish, doc: "Faker-style random email."},
    random_string: %{
      greenmask: "RandomString",
      types: @stringish,
      doc: "Random string within length bounds."
    },
    random_int: %{greenmask: "RandomInt", types: [:integer], doc: "Random integer within bounds."},
    random_float: %{greenmask: "RandomFloat", types: [:float], doc: "Random float within bounds."},
    random_username: %{
      greenmask: "RandomUsername",
      types: @stringish,
      doc: "Faker-style random username."
    },
    random_paragraph: %{
      greenmask: "RandomParagraph",
      types: @stringish,
      doc: "Faker-style random paragraph — free text."
    },
    random_phone_number: %{
      greenmask: "RandomPhoneNumber",
      types: @stringish,
      doc: "Faker-style random phone number."
    },
    random_choice: %{
      greenmask: "RandomChoice",
      types: @any,
      doc: "Random value from a provided list — NOT deterministic."
    },
    hash: %{
      greenmask: "Hash",
      types: @stringish,
      doc:
        "Deterministic salted hash (SHA-3 family; GREENMASK_GLOBAL_SALT). The referential-continuity engine."
    },
    dict: %{
      greenmask: "Dict",
      types: @stringish,
      doc: "Replace values matched by dictionary keys."
    },
    template: %{
      greenmask: "Template",
      types: @any,
      doc: "Compose a value from a template over the record."
    },
    cmd: %{
      greenmask: "Cmd",
      types: @any,
      doc:
        "Escape hatch: pipe through an external program. Executes arbitrary commands — the generated header says so on every use."
    }
  }

  @doc "The full closed mapping: name => %{greenmask: String.t(), types: list(), doc: String.t()}."
  def all, do: @transformers

  @doc "The greenmask transformer name a DSL name maps to, or nil."
  def greenmask_name(name), do: Map.get(@transformers, name)[:greenmask]

  @doc "The doc string for a DSL transformer name, or nil."
  def doc(name), do: Map.get(@transformers, name)[:doc]

  @doc """
  Whether `transformer` can target an attribute of `ash_type`.

  `:any` entries target every type. Otherwise the attribute's type must be
  in the entry's list (short types like `:string` are compared directly).
  """
  def targets?(transformer, ash_type) do
    case Map.fetch(@transformers, transformer) do
      {:ok, %{types: :any}} -> true
      {:ok, %{types: types}} -> ash_type in types
      :error -> false
    end
  end
end
