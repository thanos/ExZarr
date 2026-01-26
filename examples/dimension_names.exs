#!/usr/bin/env elixir

# Dimension Names Example
#
# This example demonstrates using named dimensions for intuitive array slicing:
# - Creating arrays with dimension names
# - Slicing by dimension names instead of numeric indices
# - Real-world examples with climate and medical imaging data
# - Best practices for dimension naming
#
# Run with: elixir examples/dimension_names.exs

Mix.install([
  {:ex_zarr, path: ".."}
])

defmodule DimensionNamesExample do
  @moduledoc """
  Demonstrates Zarr v3 dimension names feature.

  Dimension names make code more readable and less error-prone by using
  semantic labels instead of numeric indices.
  """

  def run do
    IO.puts("=== Dimension Names Example ===\n")

    example_1_climate_data()
    example_2_medical_imaging()
    example_3_validation()
    example_4_best_practices()

    IO.puts("\nAll examples completed.")
  end

  defp example_1_climate_data do
    IO.puts("Example 1: Climate Data with Named Dimensions\n")

    # Create climate dataset with intuitive dimension names
    data_dir = "/tmp/dimension_names_climate"
    File.rm_rf!(data_dir)
    File.mkdir_p!(data_dir)

    IO.puts("Creating array with dimensions: [time, latitude, longitude]")

    {:ok, array} = ExZarr.create(
      shape: {365, 180, 360},
      chunks: {1, 180, 360},
      dtype: :float32,
      dimension_names: ["time", "latitude", "longitude"],
      attributes: %{
        "description" => "Daily global temperature",
        "units" => "degrees Celsius"
      },
      codecs: [
        %{name: "bytes"},
        %{name: "gzip"}
      ],
      zarr_version: 3,
      storage: :filesystem,
      path: data_dir
    )

    IO.puts("Array created with named dimensions\n")

    # Generate and store some sample data
    IO.puts("Populating with sample temperature data...")
    populate_sample_data(array)
    IO.puts("Data populated\n")

    # Demonstrate slicing by dimension names
    IO.puts("Slicing examples:\n")

    # Example 1a: Get data for January (first 31 days)
    IO.puts("  Query: January data (time: 0..30)")
    {:ok, january} = ExZarr.Array.get_slice(array,
      time: 0..30,
      latitude: 0..179,
      longitude: 0..359
    )
    IO.puts("    Result shape: #{get_shape(january)}")
    IO.puts("    Much clearer than: start: {0, 0, 0}, stop: {31, 180, 360}\n")

    # Example 1b: Get equatorial region
    IO.puts("  Query: Equatorial region (latitude: 80..100, ±10° from equator)")
    {:ok, equator} = ExZarr.Array.get_slice(array,
      time: 0..364,          # All days
      latitude: 80..100,     # 90±10 (equator is at index 90)
      longitude: 0..359      # All longitudes
    )
    IO.puts("    Result shape: #{get_shape(equator)}")
    IO.puts("    Self-documenting what region we're selecting\n")

    # Example 1c: Northern hemisphere winter
    IO.puts("  Query: Northern hemisphere (lat: 90..179) in winter (time: 0..89)")
    {:ok, nh_winter} = ExZarr.Array.get_slice(array,
      time: 0..89,           # First 90 days (winter)
      latitude: 90..179,     # Northern hemisphere (90° = equator, 179° = ~90°N)
      longitude: 0..359
    )
    IO.puts("    Result shape: #{get_shape(nh_winter)}")
    IO.puts("    Code documents itself with dimension names\n")

    IO.puts("Benefits demonstrated:")
    IO.puts("  No need to remember which axis is which")
    IO.puts("  Code is self-documenting")
    IO.puts("  Reduces indexing errors")
    IO.puts("  Easier to maintain\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_2_medical_imaging do
    IO.puts("Example 2: Medical Imaging (MRI Scan)\n")

    data_dir = "/tmp/dimension_names_mri"
    File.rm_rf!(data_dir)
    File.mkdir_p!(data_dir)

    # MRI scan: patient × slice × row × column × time
    IO.puts("Creating 5D medical imaging array:")
    IO.puts("  Dimensions: [patient, slice, row, column, time]")
    IO.puts("  Shape: {10 patients, 20 slices, 256 rows, 256 cols, 50 time points}")

    {:ok, mri_array} = ExZarr.create(
      shape: {10, 20, 256, 256, 50},
      chunks: {1, 20, 256, 256, 50},  # One patient per chunk
      dtype: :uint16,
      dimension_names: ["patient", "slice", "row", "column", "time"],
      attributes: %{
        "modality" => "MRI",
        "description" => "Time-series MRI data",
        "units" => "arbitrary intensity units"
      },
      zarr_version: 3,
      storage: :filesystem,
      path: data_dir
    )

    IO.puts("Array created\n")

    IO.puts("Slicing examples:\n")

    # Example 2a: Get single patient's full scan
    IO.puts("  Query: Patient #5 complete scan")
    {:ok, patient_5} = ExZarr.Array.get_slice(mri_array,
      patient: 5..5,
      slice: 0..19,
      row: 0..255,
      column: 0..255,
      time: 0..49
    )
    IO.puts("    Shape: #{get_shape(patient_5)}")
    IO.puts("    Clear that we're selecting a single patient\n")

    # Example 2b: Middle slice, first timepoint (anatomical reference)
    IO.puts("  Query: Middle slice (slice: 10) at t=0 for all patients")
    {:ok, reference_slice} = ExZarr.Array.get_slice(mri_array,
      patient: 0..9,
      slice: 10..10,         # Middle slice
      row: 0..255,
      column: 0..255,
      time: 0..0             # First timepoint
    )
    IO.puts("    Shape: #{get_shape(reference_slice)}")
    IO.puts("    Dimension names make the intent clear\n")

    # Example 2c: Time series for specific voxel
    IO.puts("  Query: Time series for voxel at (patient:0, slice:10, row:128, col:128)")
    IO.puts("    Without dimension names: Would need: start: {0, 10, 128, 128, 0}, stop: {1, 11, 129, 129, 50}")
    IO.puts("    With dimension names: Much clearer!")
    IO.puts("      patient: 0..0, slice: 10..10, row: 128..128, column: 128..128, time: 0..49")

    IO.puts("\nValue for complex medical imaging:")
    IO.puts("  5D data is hard to work with using only indices")
    IO.puts("  Dimension names make code maintainable")
    IO.puts("  Prevents mistakes in complex queries")
    IO.puts("  New team members can understand queries immediately\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_3_validation do
    IO.puts("Example 3: Dimension Name Validation\n")

    data_dir = "/tmp/dimension_names_validation"
    File.rm_rf!(data_dir)

    IO.puts("Demonstrating validation rules:\n")

    # Valid: all good
    IO.puts("Valid: Correct count, unique names")
    {:ok, _array} = ExZarr.create(
      shape: {100, 200, 300},
      chunks: {10, 20, 30},
      dtype: :float32,
      dimension_names: ["x", "y", "z"],
      zarr_version: 3,
      storage: :memory
    )

    # Valid: underscores and hyphens allowed
    IO.puts("Valid: Underscores and hyphens in names")
    {:ok, _array} = ExZarr.create(
      shape: {100, 200},
      chunks: {10, 20},
      dtype: :float32,
      dimension_names: ["time_series", "spatial-index"],
      zarr_version: 3,
      storage: :memory
    )

    # Invalid: wrong count
    IO.puts("\nInvalid: Wrong number of dimension names")
    case ExZarr.create(
      shape: {100, 200, 300},
      chunks: {10, 20, 30},
      dtype: :float32,
      dimension_names: ["x", "y"],  # Only 2 names for 3D array!
      zarr_version: 3,
      storage: :memory
    ) do
      {:error, reason} ->
        IO.puts("    Error: #{inspect(reason)}")
      _ ->
        IO.puts("    Unexpected success")
    end

    # Invalid: duplicate names
    IO.puts("\nInvalid: Duplicate dimension names")
    case ExZarr.create(
      shape: {100, 200, 300},
      chunks: {10, 20, 30},
      dtype: :float32,
      dimension_names: ["x", "y", "x"],  # "x" appears twice!
      zarr_version: 3,
      storage: :memory
    ) do
      {:error, reason} ->
        IO.puts("    Error: #{inspect(reason)}")
      _ ->
        IO.puts("    Unexpected success")
    end

    IO.puts("\nValidation rules:")
    IO.puts("  1. Count must match number of dimensions")
    IO.puts("  2. All names must be unique")
    IO.puts("  3. Names can contain: letters, numbers, _, -")
    IO.puts("  4. Empty/nil names are allowed (falls back to numeric indexing)\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_4_best_practices do
    IO.puts("Example 4: Best Practices\n")

    IO.puts("Naming conventions:\n")

    IO.puts("1. Use descriptive, lowercase names:")
    IO.puts("   Good: ['time', 'latitude', 'longitude']")
    IO.puts("   Avoid: ['t', 'lat', 'lon'] (too short)")
    IO.puts("   Avoid: ['Time', 'Latitude'] (prefer lowercase)\n")

    IO.puts("2. Follow domain conventions:")
    IO.puts("   Climate: ['time', 'latitude', 'longitude', 'altitude']")
    IO.puts("   Medical: ['patient', 'slice', 'row', 'column', 'time']")
    IO.puts("   Video: ['frame', 'height', 'width', 'channel']")
    IO.puts("   Generic spatial: ['x', 'y', 'z', 't']\n")

    IO.puts("3. Be consistent:")
    IO.puts("   Use same names across related arrays in a project")
    IO.puts("   Document naming convention in project README\n")

    IO.puts("4. Consider standard names:")
    IO.puts("   CF Conventions (climate): http://cfconventions.org/")
    IO.puts("   DICOM (medical imaging): Standard anatomical terms")
    IO.puts("   Your domain's standard vocabulary\n")

    IO.puts("5. Make names self-documenting:")
    IO.puts("   'wavelength_nm' (includes units)")
    IO.puts("   'pressure_hPa'")
    IO.puts("   'time_utc'\n")

    IO.puts("Example configurations:\n")

    IO.puts(~S'''
    # Climate/Weather data
    dimension_names: ["time", "latitude", "longitude", "altitude"]

    # RGB Image stack
    dimension_names: ["image_id", "height", "width", "channel"]

    # Time-series measurements
    dimension_names: ["station", "time", "variable"]

    # Genomic data
    dimension_names: ["sample", "chromosome", "position"]

    # Particle physics
    dimension_names: ["event", "particle", "measurement"]

    # Financial data
    dimension_names: ["date", "ticker", "metric"]
    ''')

    IO.puts("\nWhen NOT to use dimension names:")
    IO.puts("  - Very generic arrays (prefer simple x, y, z or omit)")
    IO.puts("  - Internal/temporary arrays")
    IO.puts("  - When backward compatibility with v2 is required\n")
  end

  # Helper functions

  defp populate_sample_data(array) do
    # Write a few days of sample data
    for day <- 0..9 do
      data = generate_temperature_day(day)

      :ok = ExZarr.Array.set_slice(array, data,
        start: {day, 0, 0},
        stop: {day + 1, 180, 360}
      )
    end
  end

  defp generate_temperature_day(day) do
    # Generate fake temperature data for one day
    for lat <- 0..179, lon <- 0..359 do
      # Temperature varies by latitude and has some seasonal component
      base_temp = 30 - abs(lat - 90) * 0.5
      seasonal = :math.sin(2 * :math.pi * day / 365) * 10
      noise = :rand.uniform() * 5

      base_temp + seasonal + noise
    end
    |> Enum.chunk_every(360)
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  defp get_shape(data) when is_tuple(data) do
    # Recursively compute shape of nested tuple
    dims = get_dimensions(data, [])
    dims |> Enum.reverse() |> List.to_tuple() |> inspect()
  end

  defp get_dimensions(data, acc) when is_tuple(data) and tuple_size(data) > 0 do
    size = tuple_size(data)
    first = elem(data, 0)
    get_dimensions(first, [size | acc])
  end

  defp get_dimensions(_, acc), do: acc
end

# Run the example
DimensionNamesExample.run()
