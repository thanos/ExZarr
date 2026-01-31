defmodule ExZarr.SaveDiagnosticTest do
  use ExUnit.Case, async: false
  alias ExZarr.Array

  @test_dir "/tmp/ex_zarr_save_diagnostic"

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  test "diagnose v3 array save behavior" do
    path = Path.join(@test_dir, "v3_diagnostic")

    IO.puts("\n=== Creating v3 array ===")

    {:ok, array} =
      Array.create(
        shape: {10, 10},
        chunks: {5, 5},
        dtype: :int32,
        codecs: [%{name: "bytes"}, %{name: "zstd"}],
        zarr_version: 3,
        storage: :filesystem,
        path: path
      )

    IO.puts("Array created:")
    IO.puts("  version: #{inspect(array.version)}")
    IO.puts("  metadata type: #{inspect(array.metadata.__struct__)}")
    IO.puts("  storage backend: #{inspect(array.storage.backend)}")
    IO.puts("  storage path: #{inspect(array.storage.state.path)}")

    IO.puts("\n=== Checking files after create ===")
    list_directory_tree(path)

    IO.puts("\n=== Calling Array.save ===")
    result = Array.save(array, path: path)
    IO.puts("Save result: #{inspect(result)}")

    IO.puts("\n=== Checking files after save ===")
    list_directory_tree(path)

    IO.puts("\n=== Writing data ===")
    data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
    write_result = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
    IO.puts("Write result: #{inspect(write_result)}")

    IO.puts("\n=== Checking files after write ===")
    list_directory_tree(path)

    IO.puts("\n=== Attempting to reopen ===")
    open_result = Array.open(path: path)
    IO.puts("Open result: #{inspect(open_result)}")

    case open_result do
      {:ok, reopened} ->
        IO.puts("Reopened array:")
        IO.puts("  version: #{inspect(reopened.version)}")
        IO.puts("  metadata type: #{inspect(reopened.metadata.__struct__)}")

      {:error, reason} ->
        IO.puts("Failed to reopen: #{inspect(reason)}")
    end
  end

  test "diagnose v2 array save behavior" do
    path = Path.join(@test_dir, "v2_diagnostic")

    IO.puts("\n=== Creating v2 array ===")

    {:ok, array} =
      Array.create(
        shape: {10, 10},
        chunks: {5, 5},
        dtype: :int32,
        compressor: :zstd,
        zarr_version: 2,
        storage: :filesystem,
        path: path
      )

    IO.puts("Array created:")
    IO.puts("  version: #{inspect(array.version)}")
    IO.puts("  metadata type: #{inspect(array.metadata.__struct__)}")

    IO.puts("\n=== Checking files after create ===")
    list_directory_tree(path)

    IO.puts("\n=== Writing data ===")
    data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
    write_result = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
    IO.puts("Write result: #{inspect(write_result)}")

    IO.puts("\n=== Checking files after write ===")
    list_directory_tree(path)

    IO.puts("\n=== Attempting to reopen ===")
    open_result = Array.open(path: path)

    case open_result do
      {:ok, reopened} ->
        IO.puts("Reopened successfully:")
        IO.puts("  version: #{inspect(reopened.version)}")

        {:ok, read_data} = Array.get_slice(reopened, start: {0, 0}, stop: {10, 10})
        IO.puts("  data matches: #{read_data == data}")

      {:error, reason} ->
        IO.puts("Failed to reopen: #{inspect(reason)}")
    end
  end

  defp list_directory_tree(path, indent \\ 0) do
    prefix = String.duplicate("  ", indent)

    if File.exists?(path) do
      if File.dir?(path) do
        IO.puts("#{prefix}#{Path.basename(path)}/ (directory)")

        case File.ls(path) do
          {:ok, entries} ->
            Enum.sort(entries)
            |> Enum.each(fn entry ->
              list_directory_tree(Path.join(path, entry), indent + 1)
            end)

          {:error, _} ->
            IO.puts("#{prefix}  [error reading directory]")
        end
      else
        stat = File.stat!(path)
        IO.puts("#{prefix}#{Path.basename(path)} (#{stat.size} bytes)")
      end
    else
      IO.puts("#{prefix}[path does not exist: #{path}]")
    end
  end
end
