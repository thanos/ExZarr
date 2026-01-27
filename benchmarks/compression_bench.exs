# Compression Codec Benchmarks
#
# Benchmarks compression and decompression performance for various codecs
# Run with: mix run benchmarks/compression_bench.exs

# Ensure application is started
Application.ensure_all_started(:ex_zarr)

alias ExZarr.Codecs

# Generate test data of different sizes
data_1kb = :crypto.strong_rand_bytes(1024)
data_10kb = :crypto.strong_rand_bytes(10 * 1024)
data_100kb = :crypto.strong_rand_bytes(100 * 1024)
data_1mb = :crypto.strong_rand_bytes(1024 * 1024)

# Create highly compressible data (repeated patterns)
compressible_1mb = String.duplicate(<<1, 2, 3, 4>>, 256 * 1024)

IO.puts("\n=== Compression Codec Benchmarks ===\n")

# Check which codecs are available
available = Codecs.available_codecs()
IO.puts("Available codecs: #{inspect(available)}\n")

# Build benchmark scenarios based on available codecs
compression_scenarios =
  Enum.flat_map([:zlib, :blosc, :zstd, :lz4], fn codec ->
    if codec in available do
      [
        {"#{codec}/1KB", fn -> Codecs.compress(data_1kb, codec) end},
        {"#{codec}/10KB", fn -> Codecs.compress(data_10kb, codec) end},
        {"#{codec}/100KB", fn -> Codecs.compress(data_100kb, codec) end},
        {"#{codec}/1MB", fn -> Codecs.compress(data_1mb, codec) end},
        {"#{codec}/1MB_compressible", fn -> Codecs.compress(compressible_1mb, codec) end}
      ]
    else
      []
    end
  end)
  |> Enum.into(%{})

Benchee.run(
  compression_scenarios,
  time: 5,
  memory_time: 2,
  warmup: 1,
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n=== Decompression Codec Benchmarks ===\n")

# Pre-compress data for decompression benchmarks
compressed_data =
  Enum.reduce([:zlib, :blosc, :zstd, :lz4], %{}, fn codec, acc ->
    if codec in available do
      {:ok, compressed_1kb} = Codecs.compress(data_1kb, codec)
      {:ok, compressed_1mb} = Codecs.compress(data_1mb, codec)
      Map.put(acc, codec, %{kb: compressed_1kb, mb: compressed_1mb})
    else
      acc
    end
  end)

decompression_scenarios =
  Enum.flat_map([:zlib, :blosc, :zstd, :lz4], fn codec ->
    if codec in available do
      data = compressed_data[codec]
      [
        {"#{codec}/1KB", fn -> Codecs.decompress(data.kb, codec) end},
        {"#{codec}/1MB", fn -> Codecs.decompress(data.mb, codec) end}
      ]
    else
      []
    end
  end)
  |> Enum.into(%{})

Benchee.run(
  decompression_scenarios,
  time: 5,
  memory_time: 2,
  warmup: 1,
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n=== Compression Ratios ===\n")

# Calculate and display compression ratios
Enum.each([:zlib, :blosc, :zstd, :lz4], fn codec ->
  if codec in available do
    data = compressed_data[codec]
    ratio = byte_size(data_1mb) / byte_size(data.mb)
    IO.puts(
      "Random 1MB (#{codec}): #{Float.round(ratio, 2)}x (#{byte_size(data_1mb)} -> #{byte_size(data.mb)} bytes)"
    )
  end
end)
