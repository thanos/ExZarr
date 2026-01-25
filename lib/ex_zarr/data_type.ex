defmodule ExZarr.DataType do
  @moduledoc """
  Data type conversion between Zarr v2 and v3 formats.

  Zarr v2 uses NumPy-style dtype strings (e.g., "<i4", "<f8", "|b1") while
  Zarr v3 uses simplified type names (e.g., "int32", "float64", "bool").

  This module provides bidirectional conversion between:
  - Internal atoms (`:int32`, `:float64`, etc.)
  - v2 NumPy dtype strings (`"<i4"`, `"<f8"`, etc.)
  - v3 simplified type names (`"int32"`, `"float64"`, etc.)

  ## Data Type Mapping

  | Internal | v2 NumPy | v3 Name |
  |----------|----------|---------|
  | `:int8` | `"<i1"` | `"int8"` |
  | `:int16` | `"<i2"` | `"int16"` |
  | `:int32` | `"<i4"` | `"int32"` |
  | `:int64` | `"<i8"` | `"int64"` |
  | `:uint8` | `"<u1"` | `"uint8"` |
  | `:uint16` | `"<u2"` | `"uint16"` |
  | `:uint32` | `"<u4"` | `"uint32"` |
  | `:uint64` | `"<u8"` | `"uint64"` |
  | `:float32` | `"<f4"` | `"float32"` |
  | `:float64` | `"<f8"` | `"float64"` |

  ## Byte Order

  v2 uses byte order prefixes:
  - `<` : little-endian
  - `>` : big-endian
  - `|` : not applicable (single byte or unicode)

  v3 does not encode byte order in the type name (little-endian is default).

  ## Examples

      # Convert internal atom to v3 string
      iex> ExZarr.DataType.to_v3(:int32)
      "int32"

      # Convert v3 string to internal atom
      iex> ExZarr.DataType.from_v3("float64")
      :float64

      # Convert internal atom to v2 NumPy string
      iex> ExZarr.DataType.to_v2(:int32)
      "<i4"

      # Convert v2 NumPy string to internal atom
      iex> ExZarr.DataType.from_v2("<f8")
      :float64
  """

  @type dtype_atom ::
          :int8
          | :int16
          | :int32
          | :int64
          | :uint8
          | :uint16
          | :uint32
          | :uint64
          | :float32
          | :float64
  @type v2_dtype_string :: String.t()
  @type v3_data_type :: String.t()

  # Internal atom → v3 simplified name
  @atom_to_v3 %{
    int8: "int8",
    int16: "int16",
    int32: "int32",
    int64: "int64",
    uint8: "uint8",
    uint16: "uint16",
    uint32: "uint32",
    uint64: "uint64",
    float32: "float32",
    float64: "float64"
  }

  # v3 simplified name → internal atom
  @v3_to_atom Map.new(@atom_to_v3, fn {k, v} -> {v, k} end)

  # Internal atom → v2 NumPy dtype string (little-endian)
  @atom_to_v2 %{
    int8: "<i1",
    int16: "<i2",
    int32: "<i4",
    int64: "<i8",
    uint8: "<u1",
    uint16: "<u2",
    uint32: "<u4",
    uint64: "<u8",
    float32: "<f4",
    float64: "<f8"
  }

  @doc """
  Converts an internal dtype atom to a v3 data type string.

  ## Parameters

    * `dtype_atom` - Internal data type atom

  ## Returns

    * v3 data type string

  ## Examples

      iex> ExZarr.DataType.to_v3(:int32)
      "int32"

      iex> ExZarr.DataType.to_v3(:float64)
      "float64"

      iex> ExZarr.DataType.to_v3(:uint8)
      "uint8"
  """
  @spec to_v3(dtype_atom()) :: v3_data_type()
  def to_v3(dtype_atom) when is_atom(dtype_atom) do
    case Map.get(@atom_to_v3, dtype_atom) do
      nil -> raise ArgumentError, "Unknown dtype atom: #{inspect(dtype_atom)}"
      v3_name -> v3_name
    end
  end

  @doc """
  Converts a v3 data type string to an internal dtype atom.

  ## Parameters

    * `data_type_string` - v3 data type name

  ## Returns

    * Internal dtype atom

  ## Examples

      iex> ExZarr.DataType.from_v3("int32")
      :int32

      iex> ExZarr.DataType.from_v3("float64")
      :float64

      iex> ExZarr.DataType.from_v3("uint8")
      :uint8
  """
  @spec from_v3(v3_data_type()) :: dtype_atom()
  def from_v3(data_type_string) when is_binary(data_type_string) do
    case Map.get(@v3_to_atom, data_type_string) do
      nil -> raise ArgumentError, "Unknown v3 data type: #{inspect(data_type_string)}"
      atom -> atom
    end
  end

  @doc """
  Converts an internal dtype atom to a v2 NumPy dtype string.

  Returns little-endian format by default ("<" prefix).

  ## Parameters

    * `dtype_atom` - Internal data type atom

  ## Returns

    * v2 NumPy dtype string

  ## Examples

      iex> ExZarr.DataType.to_v2(:int32)
      "<i4"

      iex> ExZarr.DataType.to_v2(:float64)
      "<f8"

      iex> ExZarr.DataType.to_v2(:uint8)
      "<u1"
  """
  @spec to_v2(dtype_atom()) :: v2_dtype_string()
  def to_v2(dtype_atom) when is_atom(dtype_atom) do
    case Map.get(@atom_to_v2, dtype_atom) do
      nil -> raise ArgumentError, "Unknown dtype atom: #{inspect(dtype_atom)}"
      v2_string -> v2_string
    end
  end

  @doc """
  Converts a v2 NumPy dtype string to an internal dtype atom.

  Handles multiple byte order prefixes (<, >, |).

  ## Parameters

    * `dtype_string` - v2 NumPy-style dtype string

  ## Returns

    * Internal dtype atom

  ## Examples

      iex> ExZarr.DataType.from_v2("<i4")
      :int32

      iex> ExZarr.DataType.from_v2("<f8")
      :float64

      iex> ExZarr.DataType.from_v2("|u1")
      :uint8

      iex> ExZarr.DataType.from_v2(">i4")
      :int32
  """
  @spec from_v2(v2_dtype_string()) :: dtype_atom()
  def from_v2(dtype_string) when is_binary(dtype_string) do
    # Handle different byte order prefixes
    normalized =
      case dtype_string do
        "<" <> rest -> rest
        ">" <> rest -> rest
        "|" <> rest -> rest
        rest -> rest
      end

    # Map type code + size to internal atom
    case normalized do
      "i1" -> :int8
      "i2" -> :int16
      "i4" -> :int32
      "i8" -> :int64
      "u1" -> :uint8
      "u2" -> :uint16
      "u4" -> :uint32
      "u8" -> :uint64
      "f4" -> :float32
      "f8" -> :float64
      _ -> raise ArgumentError, "Unknown v2 dtype string: #{inspect(dtype_string)}"
    end
  end

  @doc """
  Returns the size in bytes for a given dtype.

  ## Parameters

    * `dtype` - Internal dtype atom or v3 type string

  ## Returns

    * Size in bytes

  ## Examples

      iex> ExZarr.DataType.itemsize(:int32)
      4

      iex> ExZarr.DataType.itemsize(:float64)
      8

      iex> ExZarr.DataType.itemsize("int16")
      2
  """
  @spec itemsize(dtype_atom() | v3_data_type()) :: 1 | 2 | 4 | 8
  def itemsize(dtype) when is_atom(dtype) do
    case dtype do
      :int8 -> 1
      :int16 -> 2
      :int32 -> 4
      :int64 -> 8
      :uint8 -> 1
      :uint16 -> 2
      :uint32 -> 4
      :uint64 -> 8
      :float32 -> 4
      :float64 -> 8
      _ -> raise ArgumentError, "Unknown dtype: #{inspect(dtype)}"
    end
  end

  def itemsize(data_type) when is_binary(data_type) do
    dtype_atom = from_v3(data_type)
    itemsize(dtype_atom)
  end

  @doc """
  Returns whether a dtype represents a signed integer type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if signed integer, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.signed?(:int32)
      true

      iex> ExZarr.DataType.signed?(:uint32)
      false

      iex> ExZarr.DataType.signed?(:float64)
      false
  """
  @spec signed?(dtype_atom()) :: boolean()
  def signed?(dtype) when dtype in [:int8, :int16, :int32, :int64], do: true
  def signed?(_dtype), do: false

  @doc """
  Returns whether a dtype represents an unsigned integer type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if unsigned integer, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.unsigned?(:uint32)
      true

      iex> ExZarr.DataType.unsigned?(:int32)
      false

      iex> ExZarr.DataType.unsigned?(:float64)
      false
  """
  @spec unsigned?(dtype_atom()) :: boolean()
  def unsigned?(dtype) when dtype in [:uint8, :uint16, :uint32, :uint64], do: true
  def unsigned?(_dtype), do: false

  @doc """
  Returns whether a dtype represents a floating point type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if floating point, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.float?(:float64)
      true

      iex> ExZarr.DataType.float?(:float32)
      true

      iex> ExZarr.DataType.float?(:int32)
      false
  """
  @spec float?(dtype_atom()) :: boolean()
  def float?(dtype) when dtype in [:float32, :float64], do: true
  def float?(_dtype), do: false

  @doc """
  Returns all supported internal dtype atoms.

  ## Returns

    * List of dtype atoms

  ## Examples

      iex> ExZarr.DataType.supported_types()
      [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64]
  """
  @spec supported_types() :: [dtype_atom(), ...]
  def supported_types do
    [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64]
  end

  @doc """
  Validates that a dtype is supported.

  ## Parameters

    * `dtype` - Dtype atom, v2 string, or v3 string

  ## Returns

    * `:ok` if valid
    * `{:error, reason}` if invalid

  ## Examples

      iex> ExZarr.DataType.validate(:int32)
      :ok

      iex> ExZarr.DataType.validate("float64")
      :ok

      iex> ExZarr.DataType.validate("<i4")
      :ok

      iex> ExZarr.DataType.validate(:invalid)
      {:error, :unsupported_dtype}
  """
  @spec validate(dtype_atom() | String.t()) :: :ok | {:error, :unsupported_dtype}
  def validate(dtype) when is_atom(dtype) do
    if dtype in supported_types() do
      :ok
    else
      {:error, :unsupported_dtype}
    end
  end

  def validate(dtype_string) when is_binary(dtype_string) do
    # Try v3 first
    _atom = from_v3(dtype_string)
    :ok
  rescue
    ArgumentError ->
      try do
        # Try v2
        _atom = from_v2(dtype_string)
        :ok
      rescue
        ArgumentError -> {:error, :unsupported_dtype}
      end
  end
end
