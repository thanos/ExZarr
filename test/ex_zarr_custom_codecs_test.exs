defmodule ExZarr.CustomCodecsTest do
  use ExUnit.Case
  alias ExZarr.Codecs
  alias ExZarr.Codecs.Codec

  # Test codec for examples
  defmodule TestCodec do
    @behaviour Codec

    @impl true
    def codec_id, do: :test_codec

    @impl true
    def codec_info do
      %{
        name: "Test Codec",
        version: "1.0.0",
        type: :transformation,
        description: "Test codec for unit tests"
      }
    end

    @impl true
    def available?, do: true

    @impl true
    def encode(data, opts) when is_binary(data) do
      multiplier = Keyword.get(opts, :multiplier, 2)
      {:ok, String.duplicate(data, multiplier)}
    rescue
      e -> {:error, {:encode_failed, e}}
    end

    @impl true
    def decode(data, opts) when is_binary(data) do
      divisor = Keyword.get(opts, :divisor, 2)
      size = div(byte_size(data), divisor)
      {:ok, binary_part(data, 0, size)}
    rescue
      e -> {:error, {:decode_failed, e}}
    end

    @impl true
    def validate_config(opts) do
      case Keyword.get(opts, :multiplier) do
        nil -> :ok
        n when is_integer(n) and n > 0 -> :ok
        _ -> {:error, :invalid_multiplier}
      end
    end
  end

  defmodule UnavailableCodec do
    @behaviour Codec

    @impl true
    def codec_id, do: :unavailable_codec

    @impl true
    def codec_info do
      %{
        name: "Unavailable",
        version: "1.0.0",
        type: :compression,
        description: "Always unavailable"
      }
    end

    @impl true
    def available?, do: false

    @impl true
    def encode(_data, _opts), do: {:error, :not_available}

    @impl true
    def decode(_data, _opts), do: {:error, :not_available}
  end

  defmodule InvalidCodec do
    # Missing @behaviour declaration
    def some_function, do: :ok
  end

  describe "Codec behavior" do
    test "implements?/1 detects valid codec" do
      assert Codec.implements?(TestCodec)
    end

    test "implements?/1 detects invalid codec" do
      refute Codec.implements?(InvalidCodec)
    end
  end

  describe "Registry operations" do
    setup do
      # Unregister test codec if it exists from previous test
      Codecs.unregister_codec(:test_codec)
      Codecs.unregister_codec(:unavailable_codec)
      :ok
    end

    test "register custom codec" do
      assert :ok = Codecs.register_codec(TestCodec)
      assert :test_codec in Codecs.list_codecs()
    end

    test "register fails for duplicate codec ID without force" do
      assert :ok = Codecs.register_codec(TestCodec)
      assert {:error, :already_registered} = Codecs.register_codec(TestCodec)
    end

    test "register with force overwrites existing codec" do
      assert :ok = Codecs.register_codec(TestCodec)
      assert :ok = Codecs.register_codec(TestCodec, force: true)
    end

    test "register fails for invalid codec" do
      assert {:error, :invalid_codec} = Codecs.register_codec(InvalidCodec)
    end

    test "unregister custom codec" do
      Codecs.register_codec(TestCodec)
      assert :ok = Codecs.unregister_codec(:test_codec)
      refute :test_codec in Codecs.list_codecs()
    end

    test "unregister fails for non-existent codec" do
      assert {:error, :not_found} = Codecs.unregister_codec(:nonexistent)
    end

    test "unregister fails for built-in codec" do
      assert {:error, :cannot_unregister_builtin} = Codecs.unregister_codec(:zlib)
    end

    test "list_codecs includes custom codecs" do
      Codecs.register_codec(TestCodec)
      codecs = Codecs.list_codecs()
      assert :test_codec in codecs
      assert :zlib in codecs
      assert :none in codecs
    end

    test "available_codecs includes only available custom codecs" do
      Codecs.register_codec(TestCodec)
      Codecs.register_codec(UnavailableCodec)

      available = Codecs.available_codecs()
      assert :test_codec in available
      refute :unavailable_codec in available
    end

    test "codec_info returns custom codec information" do
      Codecs.register_codec(TestCodec)
      assert {:ok, info} = Codecs.codec_info(:test_codec)
      assert info.name == "Test Codec"
      assert info.version == "1.0.0"
      assert info.type == :transformation
    end

    test "codec_info fails for unregistered codec" do
      assert {:error, :not_found} = Codecs.codec_info(:nonexistent)
    end
  end

  describe "Custom codec compression/decompression" do
    setup do
      Codecs.unregister_codec(:test_codec)
      Codecs.register_codec(TestCodec)
      :ok
    end

    test "compress with custom codec" do
      data = "hello"
      assert {:ok, encoded} = Codecs.compress(data, :test_codec)
      assert encoded == "hellohello"
    end

    test "decompress with custom codec" do
      data = "hellohello"
      assert {:ok, decoded} = Codecs.decompress(data, :test_codec)
      assert decoded == "hello"
    end

    test "round-trip with custom codec" do
      data = "test data"
      {:ok, encoded} = Codecs.compress(data, :test_codec)
      {:ok, decoded} = Codecs.decompress(encoded, :test_codec)
      assert data == decoded
    end

    test "compress with custom codec options" do
      data = "hi"
      assert {:ok, encoded} = Codecs.compress(data, :test_codec, multiplier: 3)
      assert encoded == "hihihi"
    end

    test "decompress with custom codec options" do
      # Note: decompress/2 doesn't support opts - need to update codec to handle this differently
      # For now, just test basic decompress
      data = "hihi"
      assert {:ok, decoded} = Codecs.decompress(data, :test_codec)
      assert decoded == "hi"
    end

    test "compress fails for unregistered codec" do
      Codecs.unregister_codec(:test_codec)
      assert {:error, {:unsupported_codec, :test_codec}} = Codecs.compress("data", :test_codec)
    end

    test "decompress fails for unregistered codec" do
      Codecs.unregister_codec(:test_codec)
      assert {:error, {:unsupported_codec, :test_codec}} = Codecs.decompress("data", :test_codec)
    end
  end

  describe "Codec availability" do
    setup do
      Codecs.unregister_codec(:test_codec)
      Codecs.unregister_codec(:unavailable_codec)
      :ok
    end

    test "codec_available?/1 works for custom codec" do
      Codecs.register_codec(TestCodec)
      assert Codecs.codec_available?(:test_codec)
    end

    test "codec_available?/1 returns false for unavailable custom codec" do
      Codecs.register_codec(UnavailableCodec)
      refute Codecs.codec_available?(:unavailable_codec)
    end

    test "codec_available?/1 returns false for unregistered codec" do
      refute Codecs.codec_available?(:nonexistent)
    end

    test "codec_available?/1 still works for built-in codecs" do
      assert Codecs.codec_available?(:zlib)
      assert Codecs.codec_available?(:none)
      assert Codecs.codec_available?(:crc32c)
    end
  end

  describe "Integration with built-in codecs" do
    setup do
      Codecs.unregister_codec(:test_codec)
      Codecs.register_codec(TestCodec)
      :ok
    end

    test "custom codec doesn't break built-in codecs" do
      data = "test data"

      # Built-in codec still works
      {:ok, compressed} = Codecs.compress(data, :zlib)
      {:ok, decompressed} = Codecs.decompress(compressed, :zlib)
      assert data == decompressed

      # Custom codec also works
      {:ok, encoded} = Codecs.compress(data, :test_codec)
      {:ok, decoded} = Codecs.decompress(encoded, :test_codec)
      assert data == decoded
    end

    test "can chain custom and built-in codecs" do
      data = "hello"

      # Custom then built-in
      # "hellohello"
      {:ok, step1} = Codecs.compress(data, :test_codec)
      {:ok, step2} = Codecs.compress(step1, :zlib)

      # Reverse
      {:ok, step3} = Codecs.decompress(step2, :zlib)
      {:ok, step4} = Codecs.decompress(step3, :test_codec)

      assert data == step4
    end

    test "list includes both custom and built-in codecs" do
      codecs = Codecs.list_codecs()

      # Built-in
      assert :none in codecs
      assert :zlib in codecs
      assert :crc32c in codecs

      # Custom
      assert :test_codec in codecs
    end
  end

  describe "Error handling" do
    defmodule FailingCodec do
      @behaviour Codec

      @impl true
      def codec_id, do: :failing_codec

      @impl true
      def codec_info,
        do: %{name: "Failing", version: "1.0.0", type: :compression, description: "Always fails"}

      @impl true
      def available?, do: true

      @impl true
      def encode(_data, _opts), do: {:error, :encode_failure}

      @impl true
      def decode(_data, _opts), do: {:error, :decode_failure}
    end

    setup do
      Codecs.unregister_codec(:failing_codec)
      Codecs.register_codec(FailingCodec)
      :ok
    end

    test "handles codec encode errors gracefully" do
      assert {:error, :encode_failure} = Codecs.compress("data", :failing_codec)
    end

    test "handles codec decode errors gracefully" do
      assert {:error, :decode_failure} = Codecs.decompress("data", :failing_codec)
    end
  end
end
