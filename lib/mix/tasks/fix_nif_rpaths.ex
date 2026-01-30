defmodule Mix.Tasks.FixNifRpaths do
  @moduledoc """
  Adds rpaths to compiled Zig NIF libraries for macOS dynamic library loading.

  This task runs after compilation to ensure that the Zig NIFs can find their
  dependent compression libraries at runtime on macOS.

  ## Background

  On macOS, dynamic libraries need to know where to find their dependencies at runtime.
  The Zig NIFs link against system compression libraries (zstd, lz4, snappy, blosc, bzip2),
  but without proper rpaths, the dynamic linker can't find them.

  This task uses `install_name_tool` to add rpaths for each compression library to the
  compiled .so file.

  ## Usage

  This task is automatically run after compilation via a Mix alias:

      mix compile

  Or run manually:

      mix fix_nif_rpaths

  ## Platform Support

  - **macOS**: Fully supported, adds rpaths using `install_name_tool`
  - **Linux**: Not needed (uses standard library paths)
  - **Windows**: Not supported (different dynamic library mechanism)
  """

  use Mix.Task

  @shortdoc "Adds rpaths to Zig NIF libraries on macOS"

  alias ExZarr.Codecs.CompressionConfig

  # Get compression library paths from configuration
  # This supports environment variable overrides via COMPRESSION_LIB_DIRS
  defp macos_lib_paths do
    CompressionConfig.rpath_dirs()
  end

  @impl Mix.Task
  def run(_args) do
    # Only run on macOS
    case :os.type() do
      {:unix, :darwin} ->
        fix_macos_rpaths()

      _ ->
        Mix.shell().info("Skipping rpath fix (not macOS)")
        :ok
    end
  end

  defp fix_macos_rpaths do
    nif_path = find_nif_library()

    case nif_path do
      nil ->
        # No NIF library found, probably not compiled yet
        Mix.shell().info("No Zig NIF library found, skipping rpath fix")
        :ok

      path ->
        Mix.shell().info("Adding rpaths to #{Path.basename(path)}...")
        add_rpaths(path)
    end
  end

  defp find_nif_library do
    # Look for the compiled Zig NIF library
    build_dir = Mix.Project.build_path()
    app_name = Mix.Project.config()[:app]

    nif_path =
      Path.join([
        build_dir,
        "lib",
        to_string(app_name),
        "priv",
        "lib",
        "Elixir.ExZarr.Codecs.ZigCodecs.so"
      ])

    if File.exists?(nif_path) do
      nif_path
    else
      nil
    end
  end

  defp add_rpaths(nif_path) do
    # Get existing rpaths to avoid duplicates
    existing_rpaths = get_existing_rpaths(nif_path)

    # Filter out paths that already exist and paths that don't exist on the system
    new_paths =
      macos_lib_paths()
      |> Enum.filter(&File.dir?/1)
      |> Enum.reject(&(&1 in existing_rpaths))

    case new_paths do
      [] ->
        Mix.shell().info("All rpaths already present ✓")
        :ok

      paths ->
        # Try to add rpaths
        results =
          Enum.map(paths, fn path ->
            {path, add_single_rpath(nif_path, path)}
          end)

        successful = Enum.count(results, fn {_, result} -> result == :ok end)
        failed = Enum.count(results, fn {_, result} -> result == :error end)

        if failed > 0 do
          Mix.shell().info("")

          Mix.shell().info(
            "WARNING:  Some rpaths could not be added due to Mach-O header size limits."
          )

          Mix.shell().info(
            "   To use all compression codecs, set the library path before running:"
          )

          Mix.shell().info("")

          Mix.shell().info(
            "   export DYLD_FALLBACK_LIBRARY_PATH=\"#{Enum.join(macos_lib_paths() |> Enum.filter(&File.dir?/1), ":")}\""
          )

          Mix.shell().info("")
          Mix.shell().info("   Or add it to your shell profile (~/.zshrc or ~/.bashrc)")
          Mix.shell().info("")
        end

        if successful > 0 do
          Mix.shell().info("Added #{successful} rpath(s) ✓")
        end

        :ok
    end
  end

  defp get_existing_rpaths(nif_path) do
    case System.cmd("otool", ["-l", nif_path], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse otool output to extract existing rpaths
        output
        |> String.split("\n")
        |> Enum.chunk_every(3, 1, :discard)
        |> Enum.filter(fn [line1, _line2, _line3] ->
          String.contains?(line1, "LC_RPATH")
        end)
        |> Enum.map(fn [_line1, _line2, line3] ->
          # Extract path from "         path /some/path (offset 12)"
          line3
          |> String.trim()
          |> String.split(" ")
          |> Enum.at(1)
        end)
        |> Enum.reject(&is_nil/1)

      {error, _} ->
        Mix.shell().error("Failed to read existing rpaths: #{error}")
        []
    end
  end

  defp add_single_rpath(nif_path, rpath) do
    case System.cmd("install_name_tool", ["-add_rpath", rpath, nif_path], stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("  + #{rpath}")
        :ok

      {error, _} ->
        # Check if error is just "would duplicate path" which is fine
        if String.contains?(error, "would duplicate path") do
          :ok
        else
          Mix.shell().error("  ✗ Failed to add rpath #{rpath}: #{error}")
          :error
        end
    end
  end
end
