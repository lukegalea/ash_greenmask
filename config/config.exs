import Config

# Ash 3.3x requires an explicit default for string length counting semantics.
config :ash, default_string_length_count: :mixed

if config_env() == :test do
  config :ash, :disable_all?, true
  # Test-support domains are not listed in ash_domains; skip the inclusion warning.
  config :ash, :validate_domain_config_inclusion?, false
  config :logger, level: :warning
end
