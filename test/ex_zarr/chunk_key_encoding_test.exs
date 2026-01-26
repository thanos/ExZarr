defmodule ExZarr.ChunkKeyEncodingTest do
  use ExUnit.Case, async: false

  alias ExZarr.ChunkKey

  describe "default encoders" do
    test "V2Encoder matches standard v2 encoding" do
      chunk_index = {0, 1, 2}

      v2_result = ChunkKey.V2Encoder.encode(chunk_index, [])
      direct_result = ChunkKey.encode(chunk_index, 2)

      assert v2_result == direct_result
      assert v2_result == "0.1.2"
    end

    test "V3Encoder matches standard v3 encoding" do
      chunk_index = {0, 1, 2}

      v3_result = ChunkKey.V3Encoder.encode(chunk_index, [])
      direct_result = ChunkKey.encode(chunk_index, 3)

      assert v3_result == direct_result
      assert v3_result == "c/0/1/2"
    end

    test "V2Encoder decode works correctly" do
      {:ok, decoded} = ChunkKey.V2Encoder.decode("0.1.2", [])
      assert decoded == {0, 1, 2}
    end

    test "V3Encoder decode works correctly" do
      {:ok, decoded} = ChunkKey.V3Encoder.decode("c/0/1/2", [])
      assert decoded == {0, 1, 2}
    end

    test "V2Encoder pattern matches v2 keys" do
      pattern = ChunkKey.V2Encoder.pattern([])

      assert Regex.match?(pattern, "0")
      assert Regex.match?(pattern, "0.1")
      assert Regex.match?(pattern, "0.1.2")
      refute Regex.match?(pattern, "c/0/1")
      refute Regex.match?(pattern, "invalid")
    end

    test "V3Encoder pattern matches v3 keys" do
      pattern = ChunkKey.V3Encoder.pattern([])

      assert Regex.match?(pattern, "c/0")
      assert Regex.match?(pattern, "c/0/1")
      assert Regex.match?(pattern, "c/0/1/2")
      refute Regex.match?(pattern, "0.1")
      refute Regex.match?(pattern, "invalid")
    end
  end

  describe "custom encoder" do
    defmodule TestEncoder do
      @behaviour ExZarr.ChunkKey.Encoder

      @impl true
      def encode(chunk_index, _opts) do
        indices = Tuple.to_list(chunk_index)
        "chunk_" <> Enum.join(indices, "_")
      end

      @impl true
      def decode(chunk_key, _opts) do
        case String.split(chunk_key, "_") do
          ["chunk" | indices] ->
            try do
              tuple = indices |> Enum.map(&String.to_integer/1) |> List.to_tuple()
              {:ok, tuple}
            rescue
              ArgumentError -> {:error, :invalid_chunk_key}
            end

          _ ->
            {:error, :invalid_chunk_key}
        end
      end

      @impl true
      def pattern(_opts) do
        ~r/^chunk_\d+(_\d+)*$/
      end
    end

    test "custom encoder encodes correctly" do
      result = __MODULE__.TestEncoder.encode({0, 1, 2}, [])
      assert result == "chunk_0_1_2"
    end

    test "custom encoder decodes correctly" do
      {:ok, decoded} = __MODULE__.TestEncoder.decode("chunk_0_1_2", [])
      assert decoded == {0, 1, 2}
    end

    test "custom encoder pattern matches custom keys" do
      pattern = __MODULE__.TestEncoder.pattern([])

      assert Regex.match?(pattern, "chunk_0")
      assert Regex.match?(pattern, "chunk_0_1")
      assert Regex.match?(pattern, "chunk_0_1_2")
      refute Regex.match?(pattern, "0.1")
      refute Regex.match?(pattern, "c/0/1")
    end

    test "custom encoder handles invalid keys" do
      assert {:error, :invalid_chunk_key} = __MODULE__.TestEncoder.decode("invalid", [])
      assert {:error, :invalid_chunk_key} = __MODULE__.TestEncoder.decode("chunk_", [])
      assert {:error, :invalid_chunk_key} = __MODULE__.TestEncoder.decode("chunk_a_b", [])
    end
  end

  describe "encoder registry" do
    test "default encoders are pre-registered" do
      assert {:ok, ChunkKey.V2Encoder} = ChunkKey.Registry.get(:v2)
      assert {:ok, ChunkKey.V3Encoder} = ChunkKey.Registry.get(:v3)
      assert {:ok, ChunkKey.V2Encoder} = ChunkKey.Registry.get(:default)
    end

    test "can register custom encoder" do
      ChunkKey.register_encoder(:test_format, __MODULE__.TestEncoder)

      assert {:ok, __MODULE__.TestEncoder} = ChunkKey.Registry.get(:test_format)
    end

    test "returns error for unregistered encoder" do
      assert {:error, :not_found} = ChunkKey.Registry.get(:nonexistent)
    end

    test "can overwrite existing encoder" do
      ChunkKey.register_encoder(:overwrite_test, __MODULE__.TestEncoder)
      assert {:ok, __MODULE__.TestEncoder} = ChunkKey.Registry.get(:overwrite_test)

      ChunkKey.register_encoder(:overwrite_test, ChunkKey.V2Encoder)
      assert {:ok, ChunkKey.V2Encoder} = ChunkKey.Registry.get(:overwrite_test)
    end
  end

  describe "encode_with/3" do
    setup do
      ChunkKey.register_encoder(:test, __MODULE__.TestEncoder)
      :ok
    end

    test "encodes with version number" do
      result = ChunkKey.encode_with({0, 1}, 2, [])
      assert result == "0.1"

      result = ChunkKey.encode_with({0, 1}, 3, [])
      assert result == "c/0/1"
    end

    test "encodes with registered encoder name" do
      result = ChunkKey.encode_with({0, 1, 2}, :test, [])
      assert result == "chunk_0_1_2"
    end

    test "encodes with v2/v3 encoder names" do
      result = ChunkKey.encode_with({0, 1}, :v2, [])
      assert result == "0.1"

      result = ChunkKey.encode_with({0, 1}, :v3, [])
      assert result == "c/0/1"
    end

    test "falls back to v2 for unknown encoder" do
      result = ChunkKey.encode_with({0, 1}, :unknown, [])
      assert result == "0.1"
    end

    test "handles various chunk indices" do
      assert ChunkKey.encode_with({0}, :test, []) == "chunk_0"
      assert ChunkKey.encode_with({0, 1}, :test, []) == "chunk_0_1"
      assert ChunkKey.encode_with({0, 1, 2, 3}, :test, []) == "chunk_0_1_2_3"
    end
  end

  describe "decode_with/3" do
    setup do
      ChunkKey.register_encoder(:test, __MODULE__.TestEncoder)
      :ok
    end

    test "decodes with version number" do
      {:ok, result} = ChunkKey.decode_with("0.1", 2, [])
      assert result == {0, 1}

      {:ok, result} = ChunkKey.decode_with("c/0/1", 3, [])
      assert result == {0, 1}
    end

    test "decodes with registered encoder name" do
      {:ok, result} = ChunkKey.decode_with("chunk_0_1_2", :test, [])
      assert result == {0, 1, 2}
    end

    test "decodes with v2/v3 encoder names" do
      {:ok, result} = ChunkKey.decode_with("0.1", :v2, [])
      assert result == {0, 1}

      {:ok, result} = ChunkKey.decode_with("c/0/1", :v3, [])
      assert result == {0, 1}
    end

    test "falls back to v2 for unknown encoder" do
      {:ok, result} = ChunkKey.decode_with("0.1", :unknown, [])
      assert result == {0, 1}
    end

    test "handles invalid keys" do
      assert {:error, _} = ChunkKey.decode_with("invalid", :test, [])
      assert {:error, _} = ChunkKey.decode_with("chunk_", :test, [])
    end
  end

  describe "roundtrip encoding" do
    setup do
      ChunkKey.register_encoder(:test, __MODULE__.TestEncoder)
      :ok
    end

    test "v2 encoder roundtrip" do
      indices = [{0}, {0, 1}, {0, 1, 2}, {5, 10, 15, 20}]

      for chunk_index <- indices do
        encoded = ChunkKey.encode_with(chunk_index, :v2, [])
        {:ok, decoded} = ChunkKey.decode_with(encoded, :v2, [])
        assert decoded == chunk_index
      end
    end

    test "v3 encoder roundtrip" do
      indices = [{0}, {0, 1}, {0, 1, 2}, {5, 10, 15, 20}]

      for chunk_index <- indices do
        encoded = ChunkKey.encode_with(chunk_index, :v3, [])
        {:ok, decoded} = ChunkKey.decode_with(encoded, :v3, [])
        assert decoded == chunk_index
      end
    end

    test "custom encoder roundtrip" do
      indices = [{0}, {0, 1}, {0, 1, 2}, {100, 200, 300}]

      for chunk_index <- indices do
        encoded = ChunkKey.encode_with(chunk_index, :test, [])
        {:ok, decoded} = ChunkKey.decode_with(encoded, :test, [])
        assert decoded == chunk_index
      end
    end

    test "large indices roundtrip" do
      chunk_index = {999, 1000, 2000, 3000}

      encoded = ChunkKey.encode_with(chunk_index, :test, [])
      {:ok, decoded} = ChunkKey.decode_with(encoded, :test, [])
      assert decoded == chunk_index
    end
  end

  describe "encoder behavior validation" do
    test "all encoders implement required callbacks" do
      encoders = [ChunkKey.V2Encoder, ChunkKey.V3Encoder, __MODULE__.TestEncoder]

      for encoder <- encoders do
        # Verify callbacks work by calling them
        assert is_binary(encoder.encode({0, 1}, []))

        # Verify decode returns either {:ok, _} or {:error, _}
        result = encoder.decode("0.1", [])
        assert match?({:ok, _}, result) or match?({:error, _}, result)

        assert %Regex{} = encoder.pattern([])
      end
    end

    test "encoders return correct types" do
      chunk_index = {0, 1}

      # encode returns string
      assert is_binary(ChunkKey.V2Encoder.encode(chunk_index, []))
      assert is_binary(ChunkKey.V3Encoder.encode(chunk_index, []))
      assert is_binary(__MODULE__.TestEncoder.encode(chunk_index, []))

      # pattern returns regex
      assert %Regex{} = ChunkKey.V2Encoder.pattern([])
      assert %Regex{} = ChunkKey.V3Encoder.pattern([])
      assert %Regex{} = __MODULE__.TestEncoder.pattern([])

      # decode returns {:ok, tuple} or {:error, term}
      assert {:ok, tuple} = ChunkKey.V2Encoder.decode("0.1", [])
      assert is_tuple(tuple)
    end
  end

  describe "integration with existing functionality" do
    test "encode_with works with existing chunk_key functions" do
      # Should be compatible with chunk_path and other functions
      chunk_index = {0, 1, 2}

      v2_key = ChunkKey.encode_with(chunk_index, 2, [])
      v2_path = ChunkKey.chunk_path("/data", chunk_index, 2)
      assert String.ends_with?(v2_path, v2_key)

      v3_key = ChunkKey.encode_with(chunk_index, 3, [])
      v3_path = ChunkKey.chunk_path("/data", chunk_index, 3)
      assert String.ends_with?(v3_path, v3_key)
    end

    test "decode_with is compatible with existing decode" do
      chunk_index = {5, 10}

      v2_key = ChunkKey.encode(chunk_index, 2)
      {:ok, decoded_v2} = ChunkKey.decode_with(v2_key, 2, [])
      assert decoded_v2 == chunk_index

      v3_key = ChunkKey.encode(chunk_index, 3)
      {:ok, decoded_v3} = ChunkKey.decode_with(v3_key, 3, [])
      assert decoded_v3 == chunk_index
    end
  end
end
