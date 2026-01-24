#!/usr/bin/env elixir

# Example Custom Codec Implementation
#
# This file demonstrates how to create and use custom codecs with ExZarr.
# Run with: mix run examples/custom_codec_example.exs

defmodule Examples.UppercaseCodec do
  @moduledoc """
  Example codec that converts text to uppercase on encode.

  This is a simple demonstration codec that:
  - Encodes: Converts text to uppercase
  - Decodes: Converts text back to lowercase
  - Type: transformation (not compression)
  """
  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :uppercase

  @impl true
  def codec_info do
    %{
      name: "Uppercase Transform",
      version: "1.0.0",
      type: :transformation,
      description: "Converts text to uppercase (example codec)"
    }
  end

  @impl true
  def available?, do: true

  @impl true
  def encode(data, _opts) when is_binary(data) do
    {:ok, String.upcase(data)}
  rescue
    e -> {:error, {:encode_failed, e}}
  end

  @impl true
  def decode(data, _opts) when is_binary(data) do
    {:ok, String.downcase(data)}
  rescue
    e -> {:error, {:decode_failed, e}}
  end

  @impl true
  def validate_config(_opts), do: :ok
end

defmodule Examples.RleCodec do
  @moduledoc """
  Run-Length Encoding codec (simple implementation).

  Compresses repetitive data by encoding runs of identical bytes.
  Format: [count, byte, count, byte, ...]
  """
  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :rle

  @impl true
  def codec_info do
    %{
      name: "Run-Length Encoding",
      version: "1.0.0",
      type: :compression,
      description: "Simple RLE compression for repetitive data"
    }
  end

  @impl true
  def available?, do: true

  @impl true
  def encode(data, opts) when is_binary(data) do
    threshold = Keyword.get(opts, :threshold, 3)
    {:ok, rle_encode(data, threshold)}
  rescue
    e -> {:error, {:encode_failed, e}}
  end

  @impl true
  def decode(data, _opts) when is_binary(data) do
    {:ok, rle_decode(data)}
  rescue
    e -> {:error, {:decode_failed, e}}
  end

  @impl true
  def validate_config(opts) do
    case Keyword.get(opts, :threshold) do
      nil -> :ok
      n when is_integer(n) and n > 0 -> :ok
      _ -> {:error, :invalid_threshold}
    end
  end

  # Simple RLE encoding: [count, byte, ...]
  defp rle_encode(data, threshold) do
    data
    |> :binary.bin_to_list()
    |> encode_runs([], nil, 0, threshold)
    |> :binary.list_to_bin()
  end

  defp encode_runs([], acc, nil, 0, _threshold), do: Enum.reverse(acc)

  defp encode_runs([], acc, byte, count, threshold) do
    result = if count >= threshold, do: [count, byte | acc], else: List.duplicate(byte, count) ++ acc
    Enum.reverse(result)
  end

  defp encode_runs([byte | rest], acc, byte, count, threshold) when count < 255 do
    encode_runs(rest, acc, byte, count + 1, threshold)
  end

  defp encode_runs([byte | rest], acc, byte, count, threshold) do
    # Max count reached, emit and continue
    new_acc = if count >= threshold, do: [count, byte | acc], else: List.duplicate(byte, count) ++ acc
    encode_runs(rest, new_acc, nil, 0, threshold)
  end

  defp encode_runs([new_byte | rest], acc, old_byte, count, threshold) when not is_nil(old_byte) do
    # Different byte, emit previous run
    new_acc = if count >= threshold, do: [count, old_byte | acc], else: List.duplicate(old_byte, count) ++ acc
    encode_runs([new_byte | rest], new_acc, nil, 0, threshold)
  end

  defp encode_runs([byte | rest], acc, nil, 0, threshold) do
    encode_runs(rest, acc, byte, 1, threshold)
  end

  # Simple RLE decoding
  defp rle_decode(data) do
    data
    |> :binary.bin_to_list()
    |> decode_runs([])
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  defp decode_runs([], acc), do: acc

  defp decode_runs([count, byte | rest], acc) when count > 2 do
    # This is an RLE run
    decode_runs(rest, List.duplicate(byte, count) ++ acc)
  end

  defp decode_runs([byte | rest], acc) do
    # Regular byte
    decode_runs(rest, [byte | acc])
  end
end

# ============================================
# Example Usage
# ============================================

IO.puts("═══════════════════════════════════════════")
IO.puts("  Custom Codec Example")
IO.puts("═══════════════════════════════════════════")
IO.puts("")

# 1. Register custom codecs
IO.puts("1. Registering custom codecs...")
:ok = ExZarr.Codecs.register_codec(Examples.UppercaseCodec)
:ok = ExZarr.Codecs.register_codec(Examples.RleCodec)
IO.puts("   ✓ Registered :uppercase and :rle")
IO.puts("")

# 2. List all codecs
IO.puts("2. Available codecs:")
codecs = ExZarr.Codecs.list_codecs()
IO.puts("   #{inspect(codecs)}")
IO.puts("")

# 3. Test uppercase codec
IO.puts("3. Testing Uppercase Codec:")
data = "hello, world!"
{:ok, encoded} = ExZarr.Codecs.compress(data, :uppercase)
{:ok, decoded} = ExZarr.Codecs.decompress(encoded, :uppercase)
IO.puts("   Original:  #{inspect(data)}")
IO.puts("   Encoded:   #{inspect(encoded)}")
IO.puts("   Decoded:   #{inspect(decoded)}")
IO.puts("   Match:     #{if data == decoded, do: "✓", else: "✗"}")
IO.puts("")

# 4. Test RLE codec
IO.puts("4. Testing RLE Codec:")
repetitive_data = "AAAAAABBBBBBCCCCCCDDDDDDEEEEEE"
{:ok, rle_encoded} = ExZarr.Codecs.compress(repetitive_data, :rle, threshold: 3)
{:ok, rle_decoded} = ExZarr.Codecs.decompress(rle_encoded, :rle)
ratio = Float.round(byte_size(repetitive_data) / byte_size(rle_encoded), 2)
IO.puts("   Original:  #{inspect(repetitive_data)} (#{byte_size(repetitive_data)} bytes)")
IO.puts("   Encoded:   #{byte_size(rle_encoded)} bytes")
IO.puts("   Decoded:   #{inspect(rle_decoded)} (#{byte_size(rle_decoded)} bytes)")
IO.puts("   Ratio:     #{ratio}x compression")
IO.puts("   Match:     #{if repetitive_data == rle_decoded, do: "✓", else: "✗"}")
IO.puts("")

# 5. Get codec info
IO.puts("5. Codec Information:")
{:ok, info} = ExZarr.Codecs.codec_info(:rle)
IO.puts("   Name:        #{info.name}")
IO.puts("   Version:     #{info.version}")
IO.puts("   Type:        #{info.type}")
IO.puts("   Description: #{info.description}")
IO.puts("")

# 6. Combine with built-in codecs
IO.puts("6. Using with built-in codecs:")
# First uppercase, then zlib
{:ok, step1} = ExZarr.Codecs.compress("hello world", :uppercase)
{:ok, step2} = ExZarr.Codecs.compress(step1, :zlib)
IO.puts("   Original -> Uppercase -> Zlib: #{byte_size("hello world")} -> #{byte_size(step1)} -> #{byte_size(step2)} bytes")
IO.puts("")

# 7. Unregister codec
IO.puts("7. Unregistering custom codec:")
:ok = ExZarr.Codecs.unregister_codec(:uppercase)
IO.puts("   ✓ Unregistered :uppercase")

case ExZarr.Codecs.compress("test", :uppercase) do
  {:error, {:unsupported_codec, :uppercase}} -> IO.puts("   ✓ Codec no longer available")
  _ -> IO.puts("   ✗ Codec still available")
end

IO.puts("")
IO.puts("═══════════════════════════════════════════")
IO.puts("  Example Complete!")
IO.puts("═══════════════════════════════════════════")
