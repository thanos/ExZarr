import Config

# Configure Ziggler to use the system Zig installation
if System.get_env("ZIG_PATH") do
  config :zigler,
    zig_path: System.get_env("ZIG_PATH")
end

# Compression library paths
# By default, ExZarr auto-detects library paths based on your platform:
# - macOS: Uses Homebrew paths (/opt/homebrew or /usr/local)
# - Linux: Uses standard system library paths
#
# You can override the auto-detection with environment variables:
#
# export COMPRESSION_LIB_DIRS="/custom/path/lib:/another/path/lib"
# export HOMEBREW_PREFIX="/custom/homebrew"
# export BZIP2_STATIC_LIB="/custom/path/to/libbz2.a"
#
# These environment variables must be set before compilation (mix compile).

# Import environment-specific config
import_config "#{config_env()}.exs"
