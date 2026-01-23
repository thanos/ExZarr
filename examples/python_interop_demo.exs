#!/usr/bin/env elixir

# Demonstration of ExZarr and zarr-python interoperability
#
# This script shows how arrays created by ExZarr can be read by Python's zarr library,
# and vice versa.
#
# Usage:
#   elixir examples/python_interop_demo.exs

Mix.install([{:ex_zarr, path: "."}])

defmodule PythonInteropDemo do
  def run do
    IO.puts("=== ExZarr ↔ zarr-python Interoperability Demo ===\n")

    # Create a temporary directory for the demo
    demo_dir = "/tmp/exzarr_python_demo_#{System.unique_integer([:positive])}"
    File.mkdir_p!(demo_dir)

    # Demo 1: Create with ExZarr, read with Python
    demo_exzarr_to_python(demo_dir)

    IO.puts("")

    # Demo 2: Create with Python, read with ExZarr
    demo_python_to_exzarr(demo_dir)

    # Cleanup
    File.rm_rf!(demo_dir)

    IO.puts("\n=== Demo Complete ===")
  end

  defp demo_exzarr_to_python(demo_dir) do
    IO.puts("1. Creating array with ExZarr...")

    path = Path.join(demo_dir, "exzarr_array")

    # Create a 2D array with ExZarr
    {:ok, array} =
      ExZarr.create(
        shape: {10, 10},
        chunks: {5, 5},
        dtype: :float64,
        compressor: :zlib,
        storage: :filesystem,
        path: path
      )

    :ok = ExZarr.save(array, path: path)

    IO.puts("   Created #{inspect(array.shape)} array at #{path}")
    IO.puts("   Dtype: #{array.dtype}, Compressor: #{array.compressor}")

    # Try to read with Python
    IO.puts("\n2. Reading with zarr-python...")

    case System.cmd("python3", [
           "-c",
           """
           import zarr
           import sys
           try:
               z = zarr.open_array('#{path}', mode='r')
               print(f"   Shape: {z.shape}")
               print(f"   Dtype: {z.dtype}")
               print(f"   Chunks: {z.chunks}")
               sys.exit(0)
           except Exception as e:
               print(f"   Error: {e}")
               sys.exit(1)
           """
         ]) do
      {output, 0} ->
        IO.puts(output)
        IO.puts("   ✓ Python successfully read the ExZarr array!")

      {output, _} ->
        IO.puts("   ✗ Python failed to read: #{output}")
        IO.puts("   (This is expected if zarr-python is not installed)")
    end
  end

  defp demo_python_to_exzarr(demo_dir) do
    IO.puts("3. Creating array with zarr-python...")

    path = Path.join(demo_dir, "python_array")

    # Create with Python
    case System.cmd("python3", [
           "-c",
           """
           import zarr
           import numpy as np
           import sys
           try:
               z = zarr.open_array('#{path}', mode='w', shape=(20, 20), chunks=(10, 10), dtype='int32')
               z[:, :] = np.arange(400).reshape((20, 20))
               print("   Created (20, 20) array with Python")
               print(f"   Dtype: {z.dtype}")
               sys.exit(0)
           except Exception as e:
               print(f"   Error: {e}")
               sys.exit(1)
           """
         ]) do
      {output, 0} ->
        IO.puts(output)

        # Try to read with ExZarr
        IO.puts("\n4. Reading with ExZarr...")

        case ExZarr.open(path: path) do
          {:ok, array} ->
            IO.puts("   Shape: #{inspect(array.shape)}")
            IO.puts("   Dtype: #{array.dtype}")
            IO.puts("   Chunks: #{inspect(array.chunks)}")
            IO.puts("   ✓ ExZarr successfully read the Python array!")

          {:error, reason} ->
            IO.puts("   ✗ Failed to read: #{inspect(reason)}")
        end

      {output, _} ->
        IO.puts("   ✗ Python failed to create array: #{output}")
        IO.puts("   (This is expected if zarr-python is not installed)")
        IO.puts("\n4. Skipping ExZarr read test")
    end
  end
end

# Run the demo
PythonInteropDemo.run()
