import Config

# Ash 3.3x requires an explicit default for string length counting semantics.
config :ash, default_string_length_count: :mixed

if config_env() == :test do
  config :ash, :disable_all?, true
  config :logger, level: :warning
end
