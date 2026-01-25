defmodule ExZarr.Codecs.ShardingIndexedTest do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.ShardingIndexed

  describe "init/1" do
    test "initializes with valid configuration" do
      config = %{
        "chunk_shape" => [2, 2],
        "codecs" => [%{"name" => "bytes"}],
        "index_codecs" => [%{"name" => "bytes"}],
        "index_location" => "end"
      }

      assert {:ok, codec} = ShardingIndexed.init(config)
      assert codec.chunk_shape == {2, 2}
      assert codec.codecs == [%{"name" => "bytes"}]
      assert codec.index_location == :end
    end

    test "uses default index codecs when not specified" do
      config = %{
        "chunk_shape" => [2, 2],
        "codecs" => [%{"name" => "bytes"}]
      }

      assert {:ok, codec} = ShardingIndexed.init(config)
      assert length(codec.index_codecs) == 2
      assert Enum.any?(codec.index_codecs, fn c -> c["name"] == "bytes" end)
    end

    test "defaults to end index location" do
      config = %{
        "chunk_shape" => [2, 2],
        "codecs" => [%{"name" => "bytes"}]
      }

      assert {:ok, codec} = ShardingIndexed.init(config)
      assert codec.index_location == :end
    end

    test "returns error for missing chunk_shape" do
      config = %{
        "codecs" => [%{"name" => "bytes"}]
      }

      assert {:error, :missing_chunk_shape} = ShardingIndexed.init(config)
    end

    test "returns error for missing codecs" do
      config = %{
        "chunk_shape" => [2, 2]
      }

      assert {:error, :missing_codecs} = ShardingIndexed.init(config)
    end
  end

  describe "encode/2 and decode/2" do
    setup do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [%{"name" => "bytes", "configuration" => %{}}],
          "index_codecs" => [%{"name" => "bytes", "configuration" => %{}}],
          "index_location" => "end"
        })

      {:ok, codec: codec}
    end

    test "encodes and decodes single chunk", %{codec: codec} do
      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert is_binary(shard)
      # Should include chunk data + index + index size
      assert byte_size(shard) > 4

      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end

    test "encodes and decodes multiple chunks", %{codec: codec} do
      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>,
        {0, 1} => <<5, 6, 7, 8>>,
        {1, 0} => <<9, 10, 11, 12>>,
        {1, 1} => <<13, 14, 15, 16>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert is_binary(shard)

      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end

    test "handles empty chunks map", %{codec: codec} do
      chunks = %{}

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == %{}
    end

    test "handles chunks with different sizes", %{codec: codec} do
      chunks = %{
        {0, 0} => <<1, 2>>,
        {0, 1} => <<3, 4, 5, 6, 7, 8>>,
        {1, 0} => <<9>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end
  end

  describe "decode_chunk/3" do
    setup do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}],
          "index_location" => "end"
        })

      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>,
        {0, 1} => <<5, 6, 7, 8>>,
        {1, 0} => <<9, 10, 11, 12>>,
        {1, 1} => <<13, 14, 15, 16>>
      }

      {:ok, shard} = ShardingIndexed.encode(chunks, codec)

      {:ok, codec: codec, shard: shard, chunks: chunks}
    end

    test "extracts specific chunk by index", %{codec: codec, shard: shard} do
      assert {:ok, chunk_data} = ShardingIndexed.decode_chunk(shard, {0, 1}, codec)
      assert chunk_data == <<5, 6, 7, 8>>
    end

    test "extracts all chunks individually", %{codec: codec, shard: shard, chunks: chunks} do
      for {chunk_idx, expected_data} <- chunks do
        assert {:ok, chunk_data} = ShardingIndexed.decode_chunk(shard, chunk_idx, codec)
        assert chunk_data == expected_data
      end
    end

    test "returns error for non-existent chunk", %{codec: codec, shard: shard} do
      assert {:error, {:chunk_not_found, {9, 9}}} =
               ShardingIndexed.decode_chunk(shard, {9, 9}, codec)
    end
  end

  describe "index_location :start" do
    setup do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}],
          "index_location" => "start"
        })

      {:ok, codec: codec}
    end

    test "encodes and decodes with index at start", %{codec: codec} do
      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>,
        {0, 1} => <<5, 6, 7, 8>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end

    test "can extract specific chunks with index at start", %{codec: codec} do
      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>,
        {0, 1} => <<5, 6, 7, 8>>
      }

      {:ok, shard} = ShardingIndexed.encode(chunks, codec)

      assert {:ok, chunk_data} = ShardingIndexed.decode_chunk(shard, {0, 0}, codec)
      assert chunk_data == <<1, 2, 3, 4>>

      assert {:ok, chunk_data} = ShardingIndexed.decode_chunk(shard, {0, 1}, codec)
      assert chunk_data == <<5, 6, 7, 8>>
    end
  end

  describe "with compression codecs" do
    test "works with gzip compression" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [
            %{"name" => "bytes"},
            %{"name" => "gzip", "configuration" => %{"level" => 1}}
          ],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      chunks = %{
        {0, 0} => <<1, 2, 3, 4, 5, 6, 7, 8>>,
        {0, 1} => <<9, 10, 11, 12, 13, 14, 15, 16>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)

      # Compressed shard might be smaller or larger depending on data
      assert is_binary(shard)

      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end
  end

  describe "1D chunks" do
    test "handles 1D chunk indices" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [10],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      chunks = %{
        {0} => <<1, 2, 3>>,
        {1} => <<4, 5, 6>>,
        {2} => <<7, 8, 9>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end
  end

  describe "3D chunks" do
    test "handles 3D chunk indices" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2, 2],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      chunks = %{
        {0, 0, 0} => <<1, 2>>,
        {0, 0, 1} => <<3, 4>>,
        {0, 1, 0} => <<5, 6>>,
        {1, 0, 0} => <<7, 8>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end
  end

  describe "edge cases" do
    test "handles large chunks" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      # 1MB chunk
      large_chunk = :binary.copy(<<42>>, 1_000_000)

      chunks = %{
        {0, 0} => large_chunk
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end

    test "handles many small chunks" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [10, 10],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      # 100 chunks
      chunks =
        for i <- 0..9, j <- 0..9, into: %{} do
          {{i, j}, <<i, j>>}
        end

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert map_size(decoded_chunks) == 100
    end

    test "handles empty chunk data" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [2, 2],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}]
        })

      chunks = %{
        {0, 0} => <<>>,
        {0, 1} => <<1, 2>>
      }

      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)
      assert {:ok, decoded_chunks} = ShardingIndexed.decode(shard, codec)
      assert decoded_chunks == chunks
    end
  end
end
