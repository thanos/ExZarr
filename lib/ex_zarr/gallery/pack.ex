defmodule ExZarr.Gallery.Pack do
  @moduledoc """
  Small helpers for Livebook tutorials: pack/unpack Elixir numbers into the
  row-major binaries expected by `ExZarr.Array.get_slice/2` and `set_slice/3`.

  This module is intentionally tiny and dependency-free.
  """

  @type dtype ::
          :int8
          | :uint8
          | :int16
          | :uint16
          | :int32
          | :uint32
          | :int64
          | :uint64
          | :float32
          | :float64

  @spec itemsize(dtype()) :: pos_integer()
  def itemsize(:int8), do: 1
  def itemsize(:uint8), do: 1
  def itemsize(:int16), do: 2
  def itemsize(:uint16), do: 2
  def itemsize(:int32), do: 4
  def itemsize(:uint32), do: 4
  def itemsize(:float32), do: 4
  def itemsize(:int64), do: 8
  def itemsize(:uint64), do: 8
  def itemsize(:float64), do: 8

  @doc """
  Packs a flat list of numbers into a binary for the given dtype.

  Notes:
  - ExZarr uses little-endian primitives.
  - For signed ints we use `signed-little`.
  - For floats we use IEEE 754 `float-little`.
  """
  @spec pack([number()], dtype()) :: binary()
  def pack(list, dtype) when is_list(list) do
    i = itemsize(dtype)
    expected_bytes = length(list) * i

    bin =
      list
      |> Enum.map(&pack_one(&1, dtype))
      |> IO.iodata_to_binary()

    if byte_size(bin) != expected_bytes do
      raise ArgumentError,
            "packed binary size mismatch (got #{byte_size(bin)} expected #{expected_bytes})"
    end

    bin
  end

  @doc """
  Unpacks a binary into a flat list of numbers for the given dtype.
  """
  @spec unpack(binary(), dtype()) :: [number()]
  def unpack(bin, dtype) when is_binary(bin) do
    i = itemsize(dtype)

    if rem(byte_size(bin), i) != 0 do
      raise ArgumentError,
            "binary size must be a multiple of itemsize=#{i} for dtype=#{inspect(dtype)}"
    end

    do_unpack(bin, dtype, [])
    |> Enum.reverse()
  end

  defp do_unpack(<<>>, _dtype, acc), do: acc

  defp do_unpack(bin, dtype, acc) do
    {val, rest} = unpack_one(bin, dtype)
    do_unpack(rest, dtype, [val | acc])
  end

  defp pack_one(v, :int8), do: <<round(v)::signed-little-integer-size(8)>>
  defp pack_one(v, :uint8), do: <<round(v)::unsigned-little-integer-size(8)>>
  defp pack_one(v, :int16), do: <<round(v)::signed-little-integer-size(16)>>
  defp pack_one(v, :uint16), do: <<round(v)::unsigned-little-integer-size(16)>>
  defp pack_one(v, :int32), do: <<round(v)::signed-little-integer-size(32)>>
  defp pack_one(v, :uint32), do: <<round(v)::unsigned-little-integer-size(32)>>
  defp pack_one(v, :int64), do: <<round(v)::signed-little-integer-size(64)>>
  defp pack_one(v, :uint64), do: <<round(v)::unsigned-little-integer-size(64)>>
  defp pack_one(v, :float32), do: <<v::float-little-size(32)>>
  defp pack_one(v, :float64), do: <<v::float-little-size(64)>>

  defp unpack_one(<<v::signed-little-integer-size(8), rest::binary>>, :int8), do: {v, rest}
  defp unpack_one(<<v::unsigned-little-integer-size(8), rest::binary>>, :uint8), do: {v, rest}
  defp unpack_one(<<v::signed-little-integer-size(16), rest::binary>>, :int16), do: {v, rest}
  defp unpack_one(<<v::unsigned-little-integer-size(16), rest::binary>>, :uint16), do: {v, rest}
  defp unpack_one(<<v::signed-little-integer-size(32), rest::binary>>, :int32), do: {v, rest}
  defp unpack_one(<<v::unsigned-little-integer-size(32), rest::binary>>, :uint32), do: {v, rest}
  defp unpack_one(<<v::signed-little-integer-size(64), rest::binary>>, :int64), do: {v, rest}
  defp unpack_one(<<v::unsigned-little-integer-size(64), rest::binary>>, :uint64), do: {v, rest}
  defp unpack_one(<<v::float-little-size(32), rest::binary>>, :float32), do: {v, rest}
  defp unpack_one(<<v::float-little-size(64), rest::binary>>, :float64), do: {v, rest}
end
