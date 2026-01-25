defmodule ExZarr.Codecs.CompressionConfigTest do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.CompressionConfig

  describe "library_dirs/0" do
    test "returns list of library directories" do
      dirs = CompressionConfig.library_dirs()
      assert is_list(dirs)
      # All entries should be strings
      assert Enum.all?(dirs, &is_binary/1)
    end

    test "respects COMPRESSION_LIB_DIRS environment variable" do
      original = System.get_env("COMPRESSION_LIB_DIRS")

      try do
        System.put_env("COMPRESSION_LIB_DIRS", "/custom/path1:/custom/path2")
        dirs = CompressionConfig.library_dirs()

        assert dirs == ["/custom/path1", "/custom/path2"]
      after
        if original do
          System.put_env("COMPRESSION_LIB_DIRS", original)
        else
          System.delete_env("COMPRESSION_LIB_DIRS")
        end
      end
    end

    test "returns platform-specific defaults when env var not set" do
      original = System.get_env("COMPRESSION_LIB_DIRS")

      try do
        System.delete_env("COMPRESSION_LIB_DIRS")
        dirs = CompressionConfig.library_dirs()

        case :os.type() do
          {:unix, :darwin} ->
            # macOS should return Homebrew paths
            assert Enum.empty?(dirs) == false
            assert Enum.any?(dirs, &String.contains?(&1, "homebrew"))

          {:unix, _} ->
            # Linux should return system paths
            assert Enum.any?(dirs, &String.contains?(&1, "/usr"))

          _ ->
            # Other platforms may return empty
            assert is_list(dirs)
        end
      after
        if original do
          System.put_env("COMPRESSION_LIB_DIRS", original)
        end
      end
    end
  end

  describe "rpath_dirs/0" do
    test "returns list of rpath directories" do
      dirs = CompressionConfig.rpath_dirs()
      assert is_list(dirs)
      assert Enum.all?(dirs, &is_binary/1)
    end

    test "respects COMPRESSION_LIB_DIRS environment variable" do
      original = System.get_env("COMPRESSION_LIB_DIRS")

      try do
        System.put_env("COMPRESSION_LIB_DIRS", "/rpath1:/rpath2:/rpath3")
        dirs = CompressionConfig.rpath_dirs()

        assert dirs == ["/rpath1", "/rpath2", "/rpath3"]
      after
        if original do
          System.put_env("COMPRESSION_LIB_DIRS", original)
        else
          System.delete_env("COMPRESSION_LIB_DIRS")
        end
      end
    end

    test "includes both ARM and Intel paths on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          original = System.get_env("COMPRESSION_LIB_DIRS")

          try do
            System.delete_env("COMPRESSION_LIB_DIRS")
            dirs = CompressionConfig.rpath_dirs()

            # Should include both ARM (/opt/homebrew) and Intel (/usr/local) paths
            arm_paths = Enum.filter(dirs, &String.contains?(&1, "/opt/homebrew"))
            intel_paths = Enum.filter(dirs, &String.contains?(&1, "/usr/local"))

            assert Enum.empty?(arm_paths) == false, "Should include ARM Homebrew paths"
            assert Enum.empty?(intel_paths) == false, "Should include Intel Homebrew paths"
          after
            if original, do: System.put_env("COMPRESSION_LIB_DIRS", original)
          end

        _ ->
          :ok
      end
    end

    test "returns empty list on Linux by default" do
      case :os.type() do
        {:unix, :linux} ->
          original = System.get_env("COMPRESSION_LIB_DIRS")

          try do
            System.delete_env("COMPRESSION_LIB_DIRS")
            dirs = CompressionConfig.rpath_dirs()

            assert dirs == []
          after
            if original, do: System.put_env("COMPRESSION_LIB_DIRS", original)
          end

        _ ->
          :ok
      end
    end
  end

  describe "bzip2_static_lib/0" do
    test "returns path to bzip2 static library" do
      path = CompressionConfig.bzip2_static_lib()
      assert is_binary(path)
      assert String.ends_with?(path, "libbz2.a")
    end

    test "respects BZIP2_STATIC_LIB environment variable" do
      original = System.get_env("BZIP2_STATIC_LIB")

      try do
        System.put_env("BZIP2_STATIC_LIB", "/custom/bzip2/libbz2.a")
        path = CompressionConfig.bzip2_static_lib()

        assert path == "/custom/bzip2/libbz2.a"
      after
        if original do
          System.put_env("BZIP2_STATIC_LIB", original)
        else
          System.delete_env("BZIP2_STATIC_LIB")
        end
      end
    end

    test "includes homebrew prefix on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          original = System.get_env("BZIP2_STATIC_LIB")

          try do
            System.delete_env("BZIP2_STATIC_LIB")
            path = CompressionConfig.bzip2_static_lib()

            assert String.contains?(path, "opt/bzip2")
            assert String.ends_with?(path, "lib/libbz2.a")
          after
            if original, do: System.put_env("BZIP2_STATIC_LIB", original)
          end

        _ ->
          :ok
      end
    end
  end

  describe "homebrew_prefix/0" do
    test "returns homebrew prefix path" do
      prefix = CompressionConfig.homebrew_prefix()
      assert is_binary(prefix)
    end

    test "respects HOMEBREW_PREFIX environment variable" do
      original = System.get_env("HOMEBREW_PREFIX")

      try do
        System.put_env("HOMEBREW_PREFIX", "/custom/homebrew")
        prefix = CompressionConfig.homebrew_prefix()

        assert prefix == "/custom/homebrew"
      after
        if original do
          System.put_env("HOMEBREW_PREFIX", original)
        else
          System.delete_env("HOMEBREW_PREFIX")
        end
      end
    end

    test "detects homebrew prefix on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          original = System.get_env("HOMEBREW_PREFIX")

          try do
            System.delete_env("HOMEBREW_PREFIX")
            prefix = CompressionConfig.homebrew_prefix()

            # Should be either ARM or Intel homebrew path
            assert prefix in ["/opt/homebrew", "/usr/local"] or
                     String.starts_with?(prefix, "/")
          after
            if original, do: System.put_env("HOMEBREW_PREFIX", original)
          end

        _ ->
          :ok
      end
    end

    test "handles brew command failure gracefully" do
      # This tests the fallback when brew command is not available
      # The function should still return a valid path
      prefix = CompressionConfig.homebrew_prefix()
      assert is_binary(prefix)
      assert String.length(prefix) > 0
    end
  end

  describe "platform detection" do
    test "detects correct operating system" do
      os_type = :os.type()

      case os_type do
        {:unix, :darwin} ->
          # macOS - should have Homebrew paths
          dirs = CompressionConfig.library_dirs()
          assert Enum.empty?(dirs) == false

        {:unix, :linux} ->
          # Linux - should have system paths
          dirs = CompressionConfig.library_dirs()
          assert Enum.any?(dirs, &String.contains?(&1, "/usr"))

        _ ->
          # Other platforms
          :ok
      end
    end

    test "handles different compression libraries" do
      case :os.type() do
        {:unix, :darwin} ->
          dirs = CompressionConfig.library_dirs()

          # Should include paths for all compression libraries
          expected_libs = [:zstd, :lz4, :snappy, :"c-blosc", :bzip2]

          for lib <- expected_libs do
            lib_str = Atom.to_string(lib)

            assert Enum.any?(dirs, &String.contains?(&1, lib_str)),
                   "Should include path for #{lib}"
          end

        _ ->
          :ok
      end
    end
  end

  describe "environment variable parsing" do
    test "handles colon-separated paths correctly" do
      original = System.get_env("COMPRESSION_LIB_DIRS")

      try do
        # Test with various path separators
        System.put_env("COMPRESSION_LIB_DIRS", "/path1:/path2:/path3")
        assert CompressionConfig.library_dirs() == ["/path1", "/path2", "/path3"]

        System.put_env("COMPRESSION_LIB_DIRS", "/single/path")
        assert CompressionConfig.library_dirs() == ["/single/path"]

        System.put_env("COMPRESSION_LIB_DIRS", "")
        assert CompressionConfig.library_dirs() == [""]
      after
        if original do
          System.put_env("COMPRESSION_LIB_DIRS", original)
        else
          System.delete_env("COMPRESSION_LIB_DIRS")
        end
      end
    end
  end

  describe "integration" do
    test "library_dirs and rpath_dirs can be different" do
      # On some platforms (like macOS), rpath_dirs includes more paths
      lib_dirs = CompressionConfig.library_dirs()
      rpath_dirs = CompressionConfig.rpath_dirs()

      case :os.type() do
        {:unix, :darwin} ->
          # macOS rpath should include both ARM and Intel paths
          assert length(rpath_dirs) >= length(lib_dirs)

        {:unix, :linux} ->
          # Linux: library_dirs has paths, rpath_dirs is empty
          assert Enum.empty?(lib_dirs) == false
          assert rpath_dirs == []

        _ ->
          :ok
      end
    end

    test "all paths are absolute" do
      dirs = CompressionConfig.library_dirs() ++ CompressionConfig.rpath_dirs()

      for dir <- dirs do
        assert String.starts_with?(dir, "/"), "Path #{dir} should be absolute"
      end
    end
  end
end
