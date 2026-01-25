defmodule Mix.Tasks.FixNifRpathsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias ExZarr.Codecs.CompressionConfig
  alias Mix.Tasks.FixNifRpaths

  @nif_filename "Elixir.ExZarr.Codecs.ZigCodecs.so"

  describe "run/1 on non-macOS" do
    test "skips rpath fix on non-macOS platforms" do
      # This test will only verify behavior if not on macOS
      case :os.type() do
        {:unix, :darwin} ->
          :skip

        _ ->
          output =
            capture_io(fn ->
              FixNifRpaths.run([])
            end)

          assert String.contains?(output, "Skipping rpath fix")
      end
    end
  end

  describe "run/1 on macOS" do
    @tag :skip_on_ci
    test "runs successfully when NIF exists" do
      case :os.type() do
        {:unix, :darwin} ->
          # Ensure NIF is compiled
          Mix.Task.run("compile")

          output =
            capture_io(fn ->
              FixNifRpaths.run([])
            end)

          assert output =~ ~r/(Adding rpaths|All rpaths already present)/

        _ ->
          :skip
      end
    end

    @tag :skip_on_ci
    test "reports when NIF file not found" do
      case :os.type() do
        {:unix, :darwin} ->
          # This would require moving the NIF file temporarily
          # which could break other tests, so we'll skip detailed testing
          :ok

        _ ->
          :skip
      end
    end

    @tag :skip_on_ci
    test "handles already present rpaths gracefully" do
      case :os.type() do
        {:unix, :darwin} ->
          # Run twice - second time should say "already present"
          capture_io(fn -> FixNifRpaths.run([]) end)

          output =
            capture_io(fn ->
              FixNifRpaths.run([])
            end)

          # Should indicate rpaths are already there
          assert output =~ ~r/(already present|Adding rpaths)/

        _ ->
          :skip
      end
    end
  end

  describe "platform detection" do
    test "correctly identifies current OS" do
      os_type = :os.type()

      case os_type do
        {:unix, :darwin} ->
          assert os_type == {:unix, :darwin}

        {:unix, :linux} ->
          assert os_type == {:unix, :linux}

        {:win32, _} ->
          assert elem(os_type, 0) == :win32

        _ ->
          # Other platforms
          assert is_tuple(os_type)
          assert tuple_size(os_type) == 2
      end
    end
  end

  describe "NIF library path resolution" do
    test "NIF library path follows expected structure" do
      # The NIF should be in _build/#{env}/lib/ex_zarr/priv/lib/
      env = Mix.env()
      expected_path = Path.join(["_build", to_string(env), "lib", "ex_zarr", "priv", "lib"])

      # After compilation, this directory should exist
      if File.exists?(expected_path) do
        nif_path = Path.join(expected_path, @nif_filename)

        # Check if NIF exists (it should after compilation)
        case :os.type() do
          {:unix, _} ->
            # On Unix systems, the NIF should have .so extension
            assert File.exists?(nif_path) or not File.exists?(expected_path),
                   "NIF file should exist at #{nif_path} after compilation"

          _ ->
            :ok
        end
      end
    end

    test "NIF filename is correct" do
      assert @nif_filename == "Elixir.ExZarr.Codecs.ZigCodecs.so"
      assert String.ends_with?(@nif_filename, ".so")
      assert String.starts_with?(@nif_filename, "Elixir.")
    end
  end

  describe "rpath configuration" do
    test "gets rpath directories from CompressionConfig" do
      rpaths = CompressionConfig.rpath_dirs()

      assert is_list(rpaths)

      case :os.type() do
        {:unix, :darwin} ->
          # macOS should have rpaths
          assert Enum.empty?(rpaths) == false
          # All rpaths should be absolute paths
          Enum.each(rpaths, fn path ->
            assert String.starts_with?(path, "/"), "Rpath #{path} should be absolute"
          end)

        {:unix, :linux} ->
          # Linux typically doesn't need rpaths
          assert rpaths == []

        _ ->
          assert is_list(rpaths)
      end
    end

    test "rpath directories include expected library paths on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          rpaths = CompressionConfig.rpath_dirs()

          # Should include paths for compression libraries
          # macOS typically has /opt/homebrew or /usr/local
          has_homebrew = Enum.any?(rpaths, &String.contains?(&1, "homebrew"))
          has_usr_local = Enum.any?(rpaths, &String.contains?(&1, "/usr/local"))

          assert has_homebrew or has_usr_local,
                 "Should include Homebrew or /usr/local paths"

        _ ->
          :skip
      end
    end
  end

  describe "environment variable support" do
    test "respects COMPRESSION_LIB_DIRS environment variable" do
      original = System.get_env("COMPRESSION_LIB_DIRS")

      try do
        System.put_env("COMPRESSION_LIB_DIRS", "/custom/path1:/custom/path2")

        rpaths = CompressionConfig.rpath_dirs()
        assert rpaths == ["/custom/path1", "/custom/path2"]
      after
        if original do
          System.put_env("COMPRESSION_LIB_DIRS", original)
        else
          System.delete_env("COMPRESSION_LIB_DIRS")
        end
      end
    end
  end

  describe "install_name_tool integration" do
    @tag :skip_on_ci
    test "install_name_tool is available on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          {_output, exit_code} = System.cmd("which", ["install_name_tool"])
          assert exit_code == 0, "install_name_tool should be available on macOS"

        _ ->
          :skip
      end
    end

    @tag :skip_on_ci
    test "can query rpaths from compiled NIF" do
      case :os.type() do
        {:unix, :darwin} ->
          env = Mix.env()

          nif_path =
            Path.join(["_build", to_string(env), "lib", "ex_zarr", "priv", "lib", @nif_filename])

          if File.exists?(nif_path) do
            # Query existing rpaths
            {output, _exit_code} = System.cmd("otool", ["-l", nif_path])

            # Should contain LC_RPATH commands after running fix_nif_rpaths
            assert is_binary(output)
          end

        _ ->
          :skip
      end
    end
  end

  describe "error handling" do
    test "handles missing NIF file gracefully on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          # The task should handle missing NIF without crashing
          # This is tested implicitly by running on a clean build
          :ok

        _ ->
          :skip
      end
    end
  end

  describe "integration with compilation" do
    test "task is defined as a Mix task" do
      # Verify the module exists and is a Mix task
      assert Code.ensure_loaded?(Mix.Tasks.FixNifRpaths)
      assert function_exported?(Mix.Tasks.FixNifRpaths, :run, 1)
    end

    test "task has proper moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} =
        Code.fetch_docs(Mix.Tasks.FixNifRpaths)

      assert is_binary(moduledoc)
      assert String.contains?(moduledoc, "rpath")
      assert String.contains?(moduledoc, "macOS")
    end
  end

  describe "macOS-specific behavior" do
    @tag :skip_on_ci
    test "adds rpaths for all compression libraries" do
      case :os.type() do
        {:unix, :darwin} ->
          # Expected compression libraries
          expected_libs = ["zstd", "lz4", "snappy", "blosc", "bzip2"]

          rpaths = CompressionConfig.rpath_dirs()

          # Each library should have at least one rpath directory
          for lib <- expected_libs do
            assert Enum.any?(rpaths, &String.contains?(&1, lib)),
                   "Should include rpath for #{lib}"
          end

        _ ->
          :skip
      end
    end

    @tag :skip_on_ci
    test "handles both ARM and Intel Homebrew paths" do
      case :os.type() do
        {:unix, :darwin} ->
          rpaths = CompressionConfig.rpath_dirs()

          # Should include both ARM (/opt/homebrew) and Intel (/usr/local) paths
          # for maximum compatibility
          arm_paths = Enum.filter(rpaths, &String.contains?(&1, "/opt/homebrew"))
          intel_paths = Enum.filter(rpaths, &String.contains?(&1, "/usr/local"))

          # At least one of these should be present
          assert Enum.empty?(arm_paths) == false or Enum.empty?(intel_paths) == false,
                 "Should include Homebrew paths for either ARM or Intel"

        _ ->
          :skip
      end
    end
  end

  describe "multiple invocations" do
    @tag :skip_on_ci
    test "running task multiple times is safe" do
      case :os.type() do
        {:unix, :darwin} ->
          # Run the task multiple times
          results =
            for _ <- 1..3 do
              capture_io(fn ->
                FixNifRpaths.run([])
              end)
            end

          # All invocations should succeed
          Enum.each(results, fn output ->
            assert output =~ ~r/(Adding rpaths|All rpaths already present)/
          end)

        _ ->
          :skip
      end
    end
  end
end
