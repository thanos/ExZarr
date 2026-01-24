defmodule ExZarr.ChunkKeyTest do
  use ExUnit.Case, async: true

  doctest ExZarr.ChunkKey

  describe "v2 chunk key encoding" do
    test "encodes 1D indices" do
      assert "0" = ExZarr.ChunkKey.encode({0}, 2)
      assert "42" = ExZarr.ChunkKey.encode({42}, 2)
      assert "100" = ExZarr.ChunkKey.encode({100}, 2)
    end

    test "encodes 2D indices" do
      assert "0.0" = ExZarr.ChunkKey.encode({0, 0}, 2)
      assert "1.2" = ExZarr.ChunkKey.encode({1, 2}, 2)
      assert "10.20" = ExZarr.ChunkKey.encode({10, 20}, 2)
    end

    test "encodes 3D indices" do
      assert "0.0.0" = ExZarr.ChunkKey.encode({0, 0, 0}, 2)
      assert "1.2.3" = ExZarr.ChunkKey.encode({1, 2, 3}, 2)
      assert "5.10.15" = ExZarr.ChunkKey.encode({5, 10, 15}, 2)
    end

    test "decodes chunk keys" do
      assert {:ok, {0}} = ExZarr.ChunkKey.decode("0", 2)
      assert {:ok, {42}} = ExZarr.ChunkKey.decode("42", 2)
      assert {:ok, {0, 1, 2}} = ExZarr.ChunkKey.decode("0.1.2", 2)
      assert {:ok, {10, 20, 30}} = ExZarr.ChunkKey.decode("10.20.30", 2)
    end

    test "rejects invalid v2 keys" do
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("invalid", 2)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("c/0/1", 2)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("", 2)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("-1", 2)
    end

    test "round-trip encode/decode" do
      indices = [{0}, {1, 2}, {3, 4, 5}, {10, 20, 30, 40}]

      for index <- indices do
        key = ExZarr.ChunkKey.encode(index, 2)
        assert {:ok, ^index} = ExZarr.ChunkKey.decode(key, 2)
      end
    end
  end

  describe "v3 chunk key encoding" do
    test "encodes with c/ prefix for 1D" do
      assert "c/0" = ExZarr.ChunkKey.encode({0}, 3)
      assert "c/42" = ExZarr.ChunkKey.encode({42}, 3)
      assert "c/100" = ExZarr.ChunkKey.encode({100}, 3)
    end

    test "encodes with c/ prefix for 2D" do
      assert "c/0/0" = ExZarr.ChunkKey.encode({0, 0}, 3)
      assert "c/1/2" = ExZarr.ChunkKey.encode({1, 2}, 3)
      assert "c/10/20" = ExZarr.ChunkKey.encode({10, 20}, 3)
    end

    test "encodes with c/ prefix for 3D" do
      assert "c/0/0/0" = ExZarr.ChunkKey.encode({0, 0, 0}, 3)
      assert "c/0/1/2" = ExZarr.ChunkKey.encode({0, 1, 2}, 3)
      assert "c/5/10/15" = ExZarr.ChunkKey.encode({5, 10, 15}, 3)
    end

    test "decodes chunk keys" do
      assert {:ok, {0}} = ExZarr.ChunkKey.decode("c/0", 3)
      assert {:ok, {42}} = ExZarr.ChunkKey.decode("c/42", 3)
      assert {:ok, {0, 1, 2}} = ExZarr.ChunkKey.decode("c/0/1/2", 3)
      assert {:ok, {10, 20, 30}} = ExZarr.ChunkKey.decode("c/10/20/30", 3)
    end

    test "rejects invalid v3 keys" do
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("0.1.2", 3)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("invalid", 3)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("", 3)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("c/", 3)
      assert {:error, :invalid_chunk_key} = ExZarr.ChunkKey.decode("c/-1", 3)
    end

    test "round-trip encode/decode" do
      indices = [{0}, {1, 2}, {3, 4, 5}, {10, 20, 30, 40}]

      for index <- indices do
        key = ExZarr.ChunkKey.encode(index, 3)
        assert {:ok, ^index} = ExZarr.ChunkKey.decode(key, 3)
      end
    end
  end

  describe "chunk_key_pattern/1" do
    test "v2 pattern matches valid keys" do
      pattern = ExZarr.ChunkKey.chunk_key_pattern(2)
      assert Regex.match?(pattern, "0")
      assert Regex.match?(pattern, "1.2")
      assert Regex.match?(pattern, "0.1.2")
      assert Regex.match?(pattern, "10.20.30")
    end

    test "v2 pattern rejects invalid keys" do
      pattern = ExZarr.ChunkKey.chunk_key_pattern(2)
      refute Regex.match?(pattern, "c/0")
      refute Regex.match?(pattern, "c/0/1")
      refute Regex.match?(pattern, "")
      refute Regex.match?(pattern, "invalid")
    end

    test "v3 pattern matches valid keys" do
      pattern = ExZarr.ChunkKey.chunk_key_pattern(3)
      assert Regex.match?(pattern, "c/0")
      assert Regex.match?(pattern, "c/1/2")
      assert Regex.match?(pattern, "c/0/1/2")
      assert Regex.match?(pattern, "c/10/20/30")
    end

    test "v3 pattern rejects invalid keys" do
      pattern = ExZarr.ChunkKey.chunk_key_pattern(3)
      refute Regex.match?(pattern, "0")
      refute Regex.match?(pattern, "0.1.2")
      refute Regex.match?(pattern, "")
      refute Regex.match?(pattern, "invalid")
    end
  end

  describe "valid?/2" do
    test "validates v2 keys" do
      assert ExZarr.ChunkKey.valid?("0", 2)
      assert ExZarr.ChunkKey.valid?("1.2", 2)
      assert ExZarr.ChunkKey.valid?("0.1.2", 2)
      refute ExZarr.ChunkKey.valid?("c/0", 2)
      refute ExZarr.ChunkKey.valid?("invalid", 2)
    end

    test "validates v3 keys" do
      assert ExZarr.ChunkKey.valid?("c/0", 3)
      assert ExZarr.ChunkKey.valid?("c/1/2", 3)
      assert ExZarr.ChunkKey.valid?("c/0/1/2", 3)
      refute ExZarr.ChunkKey.valid?("0", 3)
      refute ExZarr.ChunkKey.valid?("0.1.2", 3)
      refute ExZarr.ChunkKey.valid?("invalid", 3)
    end
  end

  describe "list_all/3" do
    test "lists all chunks for 1D array with v2" do
      keys = ExZarr.ChunkKey.list_all({10}, {5}, 2)
      assert keys == ["0", "1"]
    end

    test "lists all chunks for 1D array with v3" do
      keys = ExZarr.ChunkKey.list_all({10}, {5}, 3)
      assert keys == ["c/0", "c/1"]
    end

    test "lists all chunks for 2D array with v2" do
      keys = ExZarr.ChunkKey.list_all({10, 10}, {5, 5}, 2)
      assert Enum.sort(keys) == ["0.0", "0.1", "1.0", "1.1"]
    end

    test "lists all chunks for 2D array with v3" do
      keys = ExZarr.ChunkKey.list_all({10, 10}, {5, 5}, 3)
      assert Enum.sort(keys) == ["c/0/0", "c/0/1", "c/1/0", "c/1/1"]
    end

    test "handles non-aligned array dimensions" do
      # 12 elements, chunk size 5 -> needs 3 chunks
      keys = ExZarr.ChunkKey.list_all({12}, {5}, 2)
      assert keys == ["0", "1", "2"]
    end
  end

  describe "chunk_directory/2" do
    test "returns base path for v2" do
      assert ExZarr.ChunkKey.chunk_directory("/data/array", 2) == "/data/array"
    end

    test "returns c subdirectory for v3" do
      assert ExZarr.ChunkKey.chunk_directory("/data/array", 3) == "/data/array/c"
    end
  end

  describe "chunk_path/3" do
    test "builds full path for v2" do
      path = ExZarr.ChunkKey.chunk_path("/data/array", {0, 1}, 2)
      assert path == "/data/array/0.1"
    end

    test "builds full path for v3" do
      path = ExZarr.ChunkKey.chunk_path("/data/array", {0, 1}, 3)
      assert path == "/data/array/c/0/1"
    end

    test "handles 1D arrays" do
      assert ExZarr.ChunkKey.chunk_path("/data/array", {5}, 2) == "/data/array/5"
      assert ExZarr.ChunkKey.chunk_path("/data/array", {5}, 3) == "/data/array/c/5"
    end

    test "handles 3D arrays" do
      assert ExZarr.ChunkKey.chunk_path("/data/array", {1, 2, 3}, 2) == "/data/array/1.2.3"
      assert ExZarr.ChunkKey.chunk_path("/data/array", {1, 2, 3}, 3) == "/data/array/c/1/2/3"
    end
  end
end
