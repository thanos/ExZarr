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
  | `:bool` | `"\|b1"` | `"bool"` |
  | `:complex64` | `"<c8"` | `"complex64"` |
  | `:complex128` | `"<c16"` | `"complex128"` |
  | `:datetime64` | `"<M8"` | `"datetime64"` |
  | `:timedelta64` | `"<m8"` | `"timedelta64"` |

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
          | :bool
          | :complex64
          | :complex128
          | :datetime64
          | :timedelta64
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
    float64: "float64",
    bool: "bool",
    complex64: "complex64",
    complex128: "complex128",
    datetime64: "datetime64",
    timedelta64: "timedelta64"
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
    float64: "<f8",
    bool: "|b1",
    complex64: "<c8",
    complex128: "<c16",
    datetime64: "<M8",
    timedelta64: "<m8"
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
      "b1" -> :bool
      "c8" -> :complex64
      "c16" -> :complex128
      "M8" -> :datetime64
      "m8" -> :timedelta64
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
  @spec itemsize(dtype_atom() | v3_data_type()) :: 1 | 2 | 4 | 8 | 16
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
      :bool -> 1
      :complex64 -> 8
      :complex128 -> 16
      :datetime64 -> 8
      :timedelta64 -> 8
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
  Returns whether a dtype represents a boolean type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if boolean, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.bool?(:bool)
      true

      iex> ExZarr.DataType.bool?(:int32)
      false
  """
  @spec bool?(dtype_atom()) :: boolean()
  def bool?(:bool), do: true
  def bool?(_dtype), do: false

  @doc """
  Returns whether a dtype represents a complex number type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if complex, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.complex?(:complex64)
      true

      iex> ExZarr.DataType.complex?(:complex128)
      true

      iex> ExZarr.DataType.complex?(:float32)
      false
  """
  @spec complex?(dtype_atom()) :: boolean()
  def complex?(dtype) when dtype in [:complex64, :complex128], do: true
  def complex?(_dtype), do: false

  @doc """
  Returns whether a dtype represents a datetime type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if datetime, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.datetime?(:datetime64)
      true

      iex> ExZarr.DataType.datetime?(:int64)
      false
  """
  @spec datetime?(dtype_atom()) :: boolean()
  def datetime?(:datetime64), do: true
  def datetime?(_dtype), do: false

  @doc """
  Returns whether a dtype represents a timedelta type.

  ## Parameters

    * `dtype` - Internal dtype atom

  ## Returns

    * `true` if timedelta, `false` otherwise

  ## Examples

      iex> ExZarr.DataType.timedelta?(:timedelta64)
      true

      iex> ExZarr.DataType.timedelta?(:int64)
      false
  """
  @spec timedelta?(dtype_atom()) :: boolean()
  def timedelta?(:timedelta64), do: true
  def timedelta?(_dtype), do: false

  @doc """
  Returns all supported internal dtype atoms.

  ## Returns

    * List of dtype atoms

  ## Examples

      iex> ExZarr.DataType.supported_types()
      [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64, :bool, :complex64, :complex128, :datetime64, :timedelta64]
  """
  @spec supported_types() :: [dtype_atom(), ...]
  def supported_types do
    [
      :int8,
      :int16,
      :int32,
      :int64,
      :uint8,
      :uint16,
      :uint32,
      :uint64,
      :float32,
      :float64,
      :bool,
      :complex64,
      :complex128,
      :datetime64,
      :timedelta64
    ]
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

  @doc """
  Pack a value into binary format for a given dtype.

  ## Parameters

    * `value` - Value to pack
    * `dtype` - Internal dtype atom

  ## Returns

    * Binary data

  ## Examples

      iex> ExZarr.DataType.pack(42, :int32)
      <<42, 0, 0, 0>>

      iex> ExZarr.DataType.pack(true, :bool)
      <<1>>

      iex> ExZarr.DataType.pack({3.0, 4.0}, :complex64)
      <<0, 0, 64, 64, 0, 0, 128, 64>>
  """
  @spec pack(term(), atom()) :: nonempty_binary()
  def pack(value, :int8), do: <<value::signed-little-8>>
  def pack(value, :int16), do: <<value::signed-little-16>>
  def pack(value, :int32), do: <<value::signed-little-32>>
  def pack(value, :int64), do: <<value::signed-little-64>>
  def pack(value, :uint8), do: <<value::unsigned-little-8>>
  def pack(value, :uint16), do: <<value::unsigned-little-16>>
  def pack(value, :uint32), do: <<value::unsigned-little-32>>
  def pack(value, :uint64), do: <<value::unsigned-little-64>>
  def pack(value, :float32), do: <<value::float-little-32>>
  def pack(value, :float64), do: <<value::float-little-64>>

  def pack(true, :bool), do: <<1>>
  def pack(false, :bool), do: <<0>>
  def pack(0, :bool), do: <<0>>
  def pack(_, :bool), do: <<1>>

  def pack({real, imag}, :complex64) do
    <<real::float-little-32, imag::float-little-32>>
  end

  def pack({real, imag}, :complex128) do
    <<real::float-little-64, imag::float-little-64>>
  end

  def pack(%DateTime{} = dt, :datetime64) do
    micros = DateTime.to_unix(dt, :microsecond)
    <<micros::signed-little-64>>
  end

  def pack(%NaiveDateTime{} = dt, :datetime64) do
    micros = NaiveDateTime.diff(dt, ~N[1970-01-01 00:00:00], :microsecond)
    <<micros::signed-little-64>>
  end

  def pack(micros, :datetime64) when is_integer(micros) do
    <<micros::signed-little-64>>
  end

  def pack(micros, :timedelta64) when is_integer(micros) do
    <<micros::signed-little-64>>
  end

  @doc """
  Unpack a binary value into Elixir terms for a given dtype.

  ## Parameters

    * `binary` - Binary data to unpack
    * `dtype` - Internal dtype atom

  ## Returns

    * Unpacked value

  ## Examples

      iex> ExZarr.DataType.unpack(<<42, 0, 0, 0>>, :int32)
      42

      iex> ExZarr.DataType.unpack(<<1>>, :bool)
      true

      iex> ExZarr.DataType.unpack(<<0, 0, 64, 64, 0, 0, 128, 64>>, :complex64)
      {3.0, 4.0}
  """
  @spec unpack(nonempty_binary(), atom()) :: boolean() | number() | {float(), float()}
  def unpack(<<value::signed-little-8>>, :int8), do: value
  def unpack(<<value::signed-little-16>>, :int16), do: value
  def unpack(<<value::signed-little-32>>, :int32), do: value
  def unpack(<<value::signed-little-64>>, :int64), do: value
  def unpack(<<value::unsigned-little-8>>, :uint8), do: value
  def unpack(<<value::unsigned-little-16>>, :uint16), do: value
  def unpack(<<value::unsigned-little-32>>, :uint32), do: value
  def unpack(<<value::unsigned-little-64>>, :uint64), do: value
  def unpack(<<value::float-little-32>>, :float32), do: value
  def unpack(<<value::float-little-64>>, :float64), do: value

  def unpack(<<0>>, :bool), do: false
  def unpack(<<_>>, :bool), do: true

  def unpack(<<real::float-little-32, imag::float-little-32>>, :complex64) do
    {real, imag}
  end

  def unpack(<<real::float-little-64, imag::float-little-64>>, :complex128) do
    {real, imag}
  end

  def unpack(<<micros::signed-little-64>>, :datetime64) do
    micros
  end

  def unpack(<<micros::signed-little-64>>, :timedelta64) do
    micros
  end

  @doc """
  Convert a datetime value (microseconds since epoch) to an Elixir DateTime.

  ## Parameters

    * `micros` - Microseconds since Unix epoch

  ## Returns

    * DateTime struct or error

  ## Examples

      iex> ExZarr.DataType.micros_to_datetime(1609459200000000)
      {:ok, ~U[2021-01-01 00:00:00.000000Z]}
  """
  @spec micros_to_datetime(integer()) :: {:ok, DateTime.t()} | {:error, term()}
  def micros_to_datetime(micros) when is_integer(micros) do
    DateTime.from_unix(micros, :microsecond)
  end

  @doc """
  Convert an Elixir DateTime to microseconds since epoch.

  ## Parameters

    * `datetime` - DateTime struct

  ## Returns

    * Microseconds since Unix epoch

  ## Examples

      iex> ExZarr.DataType.datetime_to_micros(~U[2021-01-01 00:00:00.000000Z])
      1609459200000000
  """
  @spec datetime_to_micros(DateTime.t()) :: integer()
  def datetime_to_micros(%DateTime{} = dt) do
    DateTime.to_unix(dt, :microsecond)
  end

  @doc """
  Parse an ISO 8601 datetime string into microseconds since epoch.

  ## Parameters

    * `datetime_string` - ISO 8601 formatted string

  ## Returns

    * `{:ok, microseconds}` or `{:error, reason}`

  ## Examples

      iex> ExZarr.DataType.parse_datetime("2021-01-01T00:00:00Z")
      {:ok, 1609459200000000}
  """
  @spec parse_datetime(binary()) ::
          {:error,
           :incompatible_calendars
           | :invalid_date
           | :invalid_format
           | :invalid_time
           | :missing_offset}
          | {:ok, integer()}
  def parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, dt, _offset} -> {:ok, datetime_to_micros(dt)}
      {:error, reason} -> {:error, reason}
    end
  end
end
