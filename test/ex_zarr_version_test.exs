defmodule ExZarr.VersionTest do
  use ExUnit.Case, async: true

  doctest ExZarr.Version

  describe "detect_version/1" do
    test "detects v2 from metadata with string keys" do
      metadata = %{"zarr_format" => 2}
      assert {:ok, 2} = ExZarr.Version.detect_version(metadata)
    end

    test "detects v2 from metadata with atom keys" do
      metadata = %{zarr_format: 2}
      assert {:ok, 2} = ExZarr.Version.detect_version(metadata)
    end

    test "detects v3 from metadata with string keys" do
      metadata = %{"zarr_format" => 3}
      assert {:ok, 3} = ExZarr.Version.detect_version(metadata)
    end

    test "detects v3 from metadata with atom keys" do
      metadata = %{zarr_format: 3}
      assert {:ok, 3} = ExZarr.Version.detect_version(metadata)
    end

    test "rejects unsupported versions" do
      metadata = %{"zarr_format" => 4}
      assert {:error, {:unsupported_version, 4}} = ExZarr.Version.detect_version(metadata)
    end

    test "returns error for missing zarr_format" do
      metadata = %{"shape" => [100, 100]}
      assert {:error, :missing_zarr_format} = ExZarr.Version.detect_version(metadata)
    end

    test "returns error for non-integer version" do
      metadata = %{"zarr_format" => "2"}
      assert {:error, {:invalid_version_type, "2"}} = ExZarr.Version.detect_version(metadata)
    end

    test "handles empty metadata map" do
      metadata = %{}
      assert {:error, :missing_zarr_format} = ExZarr.Version.detect_version(metadata)
    end
  end

  describe "default_version/0" do
    test "returns default version" do
      # Should default to 3 unless configured otherwise
      version = ExZarr.Version.default_version()
      assert version in [2, 3]
    end
  end

  describe "supported_versions/0" do
    test "returns list of supported versions" do
      assert ExZarr.Version.supported_versions() == [2, 3]
    end
  end

  describe "supported?/1" do
    test "returns true for v2" do
      assert ExZarr.Version.supported?(2)
    end

    test "returns true for v3" do
      assert ExZarr.Version.supported?(3)
    end

    test "returns false for unsupported versions" do
      refute ExZarr.Version.supported?(1)
      refute ExZarr.Version.supported?(4)
      refute ExZarr.Version.supported?(10)
    end
  end

  describe "metadata_filename/2" do
    test "returns .zarray for v2 arrays" do
      assert ExZarr.Version.metadata_filename(2, :array) == ".zarray"
    end

    test "returns .zgroup for v2 groups" do
      assert ExZarr.Version.metadata_filename(2, :group) == ".zgroup"
    end

    test "returns zarr.json for v3 arrays" do
      assert ExZarr.Version.metadata_filename(3, :array) == "zarr.json"
    end

    test "returns zarr.json for v3 groups" do
      assert ExZarr.Version.metadata_filename(3, :group) == "zarr.json"
    end

    test "defaults to array if node_type not specified for v2" do
      assert ExZarr.Version.metadata_filename(2) == ".zarray"
    end

    test "returns zarr.json if node_type not specified for v3" do
      assert ExZarr.Version.metadata_filename(3) == "zarr.json"
    end
  end
end
