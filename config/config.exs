import Config

# Configure Ziggler to use the system Zig installation
if System.get_env("ZIG_PATH") do
  config :zigler,
    zig_path: System.get_env("ZIG_PATH")
end

# Import environment-specific config
import_config "#{config_env()}.exs"
