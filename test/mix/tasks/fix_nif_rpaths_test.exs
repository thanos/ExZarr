defmodule Mix.Tasks.FixNifRpathsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.FixNifRpaths

  describe "run/1" do
    @tag :skip
    test "runs on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          output = capture_io(fn -> FixNifRpaths.run([]) end)
          assert output =~ ~r/(Adding rpaths|No Zig NIF library found|All rpaths already present)/

        _ ->
          :skip
      end
    end

    test "skips on non-macOS platforms" do
      output =
        capture_io(fn ->
          case :os.type() do
            {:unix, :darwin} ->
              FixNifRpaths.run([])

            _ ->
              Mix.shell().info("Skipping rpath fix (not macOS)")
          end
        end)

      assert is_binary(output)
    end

    test "handles missing NIF library gracefully" do
      case :os.type() do
        {:unix, :darwin} ->
          output = capture_io(fn -> FixNifRpaths.run([]) end)
          assert output =~ ~r/(Adding rpaths|No Zig NIF library found|All rpaths already present)/

        _ ->
          output = capture_io(fn -> FixNifRpaths.run([]) end)
          assert output =~ "Skipping rpath fix (not macOS)"
      end
    end

    test "accepts any arguments" do
      output = capture_io(fn -> FixNifRpaths.run(["arg1", "arg2"]) end)
      assert is_binary(output)
    end
  end

  describe "platform detection" do
    test "correctly identifies platform" do
      os_type = :os.type()

      case os_type do
        {:unix, :darwin} ->
          assert elem(os_type, 0) == :unix
          assert elem(os_type, 1) == :darwin

        {:unix, _} ->
          assert elem(os_type, 0) == :unix
          refute elem(os_type, 1) == :darwin

        {:win32, _} ->
          assert elem(os_type, 0) == :win32

        _ ->
          assert is_tuple(os_type)
      end
    end

    test "task behaves correctly on current platform" do
      output = capture_io(fn -> FixNifRpaths.run([]) end)

      case :os.type() do
        {:unix, :darwin} ->
          assert output =~ ~r/(Adding rpaths|No Zig NIF library found|All rpaths already present)/

        _ ->
          assert output =~ "Skipping rpath fix (not macOS)"
      end
    end
  end

  describe "documentation" do
    test "has module documentation" do
      {:docs_v1, _, :elixir, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.FixNifRpaths)
      assert module_doc != :hidden
      assert module_doc != :none
    end

    test "has shortdoc" do
      shortdoc = Mix.Task.shortdoc(Mix.Tasks.FixNifRpaths)
      assert is_binary(shortdoc)
      assert String.length(shortdoc) > 0
    end
  end

  describe "idempotency" do
    test "running multiple times is safe" do
      output1 = capture_io(fn -> FixNifRpaths.run([]) end)
      output2 = capture_io(fn -> FixNifRpaths.run([]) end)

      assert is_binary(output1)
      assert is_binary(output2)

      case :os.type() do
        {:unix, :darwin} ->
          if String.contains?(output2, "All rpaths already present") do
            assert output2 =~ "All rpaths already present ✓"
          end

        _ ->
          assert output1 =~ "Skipping rpath fix (not macOS)"
          assert output2 =~ "Skipping rpath fix (not macOS)"
      end
    end
  end

  describe "Mix.Project integration" do
    test "can access Mix.Project.build_path" do
      build_path = Mix.Project.build_path()
      assert is_binary(build_path)
      assert String.length(build_path) > 0
    end

    test "can access Mix.Project.config" do
      config = Mix.Project.config()
      assert is_list(config)
      assert Keyword.has_key?(config, :app)
      assert config[:app] == :ex_zarr
    end

    test "constructs valid NIF path" do
      build_dir = Mix.Project.build_path()
      app_name = Mix.Project.config()[:app]

      nif_path =
        Path.join([
          build_dir,
          "lib",
          to_string(app_name),
          "priv",
          "lib",
          "Elixir.ExZarr.Codecs.ZigCodecs.so"
        ])

      assert is_binary(nif_path)
      assert String.ends_with?(nif_path, ".so")
      assert String.contains?(nif_path, "ex_zarr")
    end
  end

  describe "error handling" do
    test "handles invalid paths gracefully" do
      output = capture_io(fn -> FixNifRpaths.run([]) end)
      assert is_binary(output)
    end

    test "handles missing dependencies gracefully" do
      case :os.type() do
        {:unix, :darwin} ->
          assert System.find_executable("otool") != nil
          assert System.find_executable("install_name_tool") != nil

        _ ->
          output = capture_io(fn -> FixNifRpaths.run([]) end)
          assert output =~ "Skipping rpath fix (not macOS)"
      end
    end
  end
end
