#!/usr/bin/env elixir

# Climate Data Processing with ExZarr
#
# This example demonstrates a real-world workflow for processing climate data:
# - Creating multi-dimensional arrays for temperature and precipitation
# - Using dimension names for intuitive slicing
# - Efficient chunking for time-series data
# - Compression to reduce storage
# - Computing statistics over time periods
#
# Run with: elixir examples/climate_data.exs

Mix.install([
  {:ex_zarr, path: ".."}
])

defmodule ClimateDataExample do
  @moduledoc """
  Example of processing climate data with ExZarr.

  Simulates storing and analyzing global temperature and precipitation data
  with dimensions: [time, latitude, longitude]
  """

  # Data dimensions
  @days 365
  @latitudes 180  # 1 degree resolution
  @longitudes 360  # 1 degree resolution

  def run do
    IO.puts("=== Climate Data Processing Example ===\n")

    # Create output directory
    data_dir = "/tmp/climate_example"
    File.rm_rf!(data_dir)
    File.mkdir_p!(data_dir)

    IO.puts("Data directory: #{data_dir}\n")

    # Step 1: Create arrays for temperature and precipitation
    IO.puts("Step 1: Creating climate data arrays...")
    {:ok, temp_array} = create_temperature_array(data_dir)
    {:ok, precip_array} = create_precipitation_array(data_dir)
    IO.puts("Arrays created\n")

    # Step 2: Generate and store simulated climate data
    IO.puts("Step 2: Generating simulated climate data...")
    populate_temperature_data(temp_array)
    populate_precipitation_data(precip_array)
    IO.puts("Data generated and stored\n")

    # Step 3: Query data by time period
    IO.puts("Step 3: Querying data for January (days 0-30)...")
    january_stats = compute_monthly_stats(temp_array, 0, 31)
    IO.puts("  Average temperature: #{Float.round(january_stats.mean, 2)}°C")
    IO.puts("  Min temperature: #{Float.round(january_stats.min, 2)}°C")
    IO.puts("  Max temperature: #{Float.round(january_stats.max, 2)}°C\n")

    # Step 4: Query data by region
    IO.puts("Step 4: Querying data for Northern Hemisphere...")
    northern_stats = compute_regional_stats(temp_array, lat_range: {0, 89})
    IO.puts("  Average temperature: #{Float.round(northern_stats.mean, 2)}°C")
    IO.puts("  Seasonal variation: #{Float.round(northern_stats.std, 2)}°C\n")

    # Step 5: Extract time series for a specific location
    IO.puts("Step 5: Extracting time series for London (51.5°N, 0°W)...")
    london_temps = extract_time_series(temp_array, lat: 51, lon: 0)
    IO.puts("  Annual average: #{Float.round(Enum.sum(london_temps) / length(london_temps), 2)}°C")
    IO.puts("  Coldest day: Day #{Enum.find_index(london_temps, &(&1 == Enum.min(london_temps)))} (#{Float.round(Enum.min(london_temps), 2)}°C)")
    IO.puts("  Warmest day: Day #{Enum.find_index(london_temps, &(&1 == Enum.max(london_temps)))} (#{Float.round(Enum.max(london_temps), 2)}°C)\n")

    # Step 6: Compute correlation between temperature and precipitation
    IO.puts("Step 6: Computing temperature-precipitation correlation...")
    correlation = compute_correlation(temp_array, precip_array)
    IO.puts("  Global correlation: #{Float.round(correlation, 3)}\n")

    # Step 7: Show storage efficiency
    IO.puts("Step 7: Storage efficiency:")
    temp_size = get_array_size("#{data_dir}/temperature")
    precip_size = get_array_size("#{data_dir}/precipitation")
    total_size = temp_size + precip_size

    # Calculate uncompressed size
    temp_uncompressed = @days * @latitudes * @longitudes * 4  # float32 = 4 bytes
    precip_uncompressed = @days * @latitudes * @longitudes * 4
    uncompressed_total = temp_uncompressed + precip_uncompressed

    compression_ratio = uncompressed_total / total_size

    IO.puts("  Uncompressed size: #{format_size(uncompressed_total)}")
    IO.puts("  Compressed size: #{format_size(total_size)}")
    IO.puts("  Compression ratio: #{Float.round(compression_ratio, 2)}x\n")

    IO.puts("Example completed.")
    IO.puts("\nArrays stored at:")
    IO.puts("  - #{data_dir}/temperature")
    IO.puts("  - #{data_dir}/precipitation")
    IO.puts("\nYou can open these arrays with Python zarr or other tools.")
  end

  defp create_temperature_array(data_dir) do
    ExZarr.create(
      shape: {@days, @latitudes, @longitudes},
      chunks: {1, @latitudes, @longitudes},  # One day per chunk for time-series access
      dtype: :float32,
      dimension_names: ["time", "latitude", "longitude"],
      codecs: [
        %{name: "bytes"},
        %{name: "zstd", configuration: %{level: 3}}  # Fast compression
      ],
      attributes: %{
        "units" => "degrees Celsius",
        "description" => "Daily global surface temperature",
        "source" => "Simulated data",
        "time_coverage" => "365 days",
        "spatial_resolution" => "1 degree"
      },
      zarr_version: 3,
      storage: :filesystem,
      path: "#{data_dir}/temperature"
    )
  end

  defp create_precipitation_array(data_dir) do
    ExZarr.create(
      shape: {@days, @latitudes, @longitudes},
      chunks: {1, @latitudes, @longitudes},
      dtype: :float32,
      dimension_names: ["time", "latitude", "longitude"],
      codecs: [
        %{name: "bytes"},
        %{name: "zstd", configuration: %{level: 3}}
      ],
      attributes: %{
        "units" => "mm",
        "description" => "Daily precipitation",
        "source" => "Simulated data"
      },
      zarr_version: 3,
      storage: :filesystem,
      path: "#{data_dir}/precipitation"
    )
  end

  defp populate_temperature_data(array) do
    IO.puts("  Generating temperature data (365 days × 180° × 360°)...")

    # Generate data in parallel by month
    tasks = for month <- 0..11 do
      Task.async(fn ->
        days_in_month = div(@days, 12)
        start_day = month * days_in_month
        end_day = min(start_day + days_in_month, @days)

        for day <- start_day..(end_day - 1) do
          # Generate temperature data for this day
          day_data = generate_temperature_field(day)

          :ok = ExZarr.Array.set_slice(array, day_data,
            start: {day, 0, 0},
            stop: {day + 1, @latitudes, @longitudes}
          )
        end

        month
      end)
    end

    Task.await_many(tasks, :infinity)
  end

  defp populate_precipitation_data(array) do
    IO.puts("  Generating precipitation data (365 days × 180° × 360°)...")

    # Generate precipitation data month by month
    for month <- 0..11 do
      days_in_month = div(@days, 12)
      start_day = month * days_in_month
      end_day = min(start_day + days_in_month, @days)

      for day <- start_day..(end_day - 1) do
        day_data = generate_precipitation_field(day)

        :ok = ExZarr.Array.set_slice(array, day_data,
          start: {day, 0, 0},
          stop: {day + 1, @latitudes, @longitudes}
        )
      end
    end
  end

  defp generate_temperature_field(day) do
    # Simulate realistic temperature patterns
    # - Seasonal variation (warmer in summer for northern hemisphere)
    # - Latitudinal gradient (warmer at equator)
    # - Some random variation

    season_factor = :math.cos(2 * :math.pi * day / 365)  # -1 to 1

    for lat <- 0..(@latitudes - 1), lon <- 0..(@longitudes - 1) do
      # Convert to actual latitude (-90 to 90)
      actual_lat = lat - 90

      # Base temperature decreases from equator (warm) to poles (cold)
      base_temp = 30 - abs(actual_lat) * 0.5

      # Seasonal variation (stronger at higher latitudes)
      seasonal_variation = season_factor * abs(actual_lat) / 10

      # Add some random noise
      noise = :rand.normal(0, 2)

      base_temp + seasonal_variation + noise
    end
    |> Enum.chunk_every(@longitudes)
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  defp generate_precipitation_field(day) do
    # Simulate precipitation patterns
    # - Higher near equator (tropical rain)
    # - Seasonal patterns
    # - Random variation (weather is chaotic!)

    season_factor = :math.sin(2 * :math.pi * day / 365)

    for lat <- 0..(@latitudes - 1), lon <- 0..(@longitudes - 1) do
      actual_lat = lat - 90

      # More rain near equator and mid-latitudes
      base_precip = cond do
        abs(actual_lat) < 10 -> 10  # Tropical rain belt
        abs(actual_lat) > 60 -> 2   # Polar regions (dry)
        true -> 5                    # Mid-latitudes
      end

      # Seasonal variation
      seasonal = season_factor * 3

      # Heavy random variation (precipitation is spotty)
      noise = :rand.uniform() * 15

      max(0, base_precip + seasonal + noise)
    end
    |> Enum.chunk_every(@longitudes)
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  defp compute_monthly_stats(array, start_day, end_day) do
    # Read temperature data for time period
    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {start_day, 0, 0},
      stop: {end_day, @latitudes, @longitudes}
    )

    # Flatten nested tuples to compute statistics
    values = data
    |> Tuple.to_list()
    |> Enum.flat_map(&Tuple.to_list/1)
    |> Enum.flat_map(&Tuple.to_list/1)

    %{
      mean: Enum.sum(values) / length(values),
      min: Enum.min(values),
      max: Enum.max(values),
      std: compute_std(values)
    }
  end

  defp compute_regional_stats(array, lat_range: {lat_start, lat_stop}) do
    # Read data for specific latitude range across all time
    lat_start_idx = lat_start + 90  # Convert to 0-180 index
    lat_stop_idx = lat_stop + 90

    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {0, lat_start_idx, 0},
      stop: {@days, lat_stop_idx + 1, @longitudes}
    )

    values = data
    |> Tuple.to_list()
    |> Enum.flat_map(&Tuple.to_list/1)
    |> Enum.flat_map(&Tuple.to_list/1)

    %{
      mean: Enum.sum(values) / length(values),
      std: compute_std(values)
    }
  end

  defp extract_time_series(array, lat: lat, lon: lon) do
    # Extract temperature time series for a specific location
    lat_idx = lat + 90
    lon_idx = lon + 180  # Wrap longitude

    # Read entire time series for this location
    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {0, lat_idx, lon_idx},
      stop: {@days, lat_idx + 1, lon_idx + 1}
    )

    # Extract values from nested tuples
    data
    |> Tuple.to_list()
    |> Enum.map(fn day ->
      day |> elem(0) |> elem(0)
    end)
  end

  defp compute_correlation(temp_array, precip_array) do
    # Sample a few points for correlation analysis
    sample_points = [
      {0, 90, 0},    # Equator
      {0, 120, 0},   # Mid-latitude north
      {0, 60, 0},    # Mid-latitude south
      {0, 150, 180}  # High latitude
    ]

    correlations = Enum.map(sample_points, fn {day, lat, lon} ->
      # Get time series for this location
      {:ok, temp_data} = ExZarr.Array.get_slice(temp_array,
        start: {day, lat, lon},
        stop: {min(day + 30, @days), lat + 1, lon + 1}
      )

      {:ok, precip_data} = ExZarr.Array.get_slice(precip_array,
        start: {day, lat, lon},
        stop: {min(day + 30, @days), lat + 1, lon + 1}
      )

      temps = temp_data |> Tuple.to_list() |> Enum.map(&(elem(elem(&1, 0), 0)))
      precips = precip_data |> Tuple.to_list() |> Enum.map(&(elem(elem(&1, 0), 0)))

      compute_pearson(temps, precips)
    end)

    # Average correlation across sample points
    Enum.sum(correlations) / length(correlations)
  end

  defp compute_std(values) do
    mean = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, fn x -> :math.pow(x - mean, 2) end)) / length(values)
    :math.sqrt(variance)
  end

  defp compute_pearson(x, y) do
    n = length(x)
    mean_x = Enum.sum(x) / n
    mean_y = Enum.sum(y) / n

    cov = Enum.zip(x, y)
    |> Enum.map(fn {xi, yi} -> (xi - mean_x) * (yi - mean_y) end)
    |> Enum.sum()

    std_x = :math.sqrt(Enum.map(x, fn xi -> :math.pow(xi - mean_x, 2) end) |> Enum.sum())
    std_y = :math.sqrt(Enum.map(y, fn yi -> :math.pow(yi - mean_y, 2) end) |> Enum.sum())

    cov / (std_x * std_y)
  end

  defp get_array_size(path) do
    case File.ls(path) do
      {:ok, files} ->
        Enum.reduce(files, 0, fn file, acc ->
          file_path = Path.join(path, file)
          case File.stat(file_path) do
            {:ok, %{size: size, type: :regular}} -> acc + size
            {:ok, %{type: :directory}} -> acc + get_array_size(file_path)
            _ -> acc
          end
        end)

      _ -> 0
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_size(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
end

# Run the example
ClimateDataExample.run()
