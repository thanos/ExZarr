defmodule Mix.Tasks.Livebook.Test do
  use Mix.Task

  @shortdoc "Run .livemd notebooks as tests by executing their Elixir code fences"

  @moduledoc """
  Discovers .livemd files, extracts elixir fenced blocks, writes a temp .exs, and runs it.

  Why this exists:
  - No dependency on Livebook
  - CI-friendly
  - Catches broken cells / stale code in docs

  Usage:
    mix livebook.test
    mix livebook.test --paths "livebooks/**/*.livemd" --paths "docs/**/*.livemd"
    mix livebook.test --pattern ExZarr --max 4 --timeout 300
    mix livebook.test --fail-on-warn
    mix livebook.test --skip-tag "livebook:test skip"
  """

  @default_paths ["livebooks/**/*.livemd", "docs/**/*.livemd"]
  @default_timeout_sec 300
  @default_max System.schedulers_online()

  @impl true
  def run(args) do
    # Note: We don't start the app here because livebooks use Mix.install
    # to create isolated environments with their own dependencies

    {opts, _rest, invalid} =
      OptionParser.parse(args,
        switches: [
          paths: :keep,
          pattern: :string,
          max: :integer,
          timeout: :integer,
          fail_on_warn: :boolean,
          skip_tag: :string
        ],
        aliases: [p: :paths]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    patterns =
      case Keyword.get_values(opts, :paths) do
        [] -> @default_paths
        ps -> ps
      end

    filter_pattern = Keyword.get(opts, :pattern)
    max_conc = Keyword.get(opts, :max, @default_max)
    timeout_sec = Keyword.get(opts, :timeout, @default_timeout_sec)
    fail_on_warn? = Keyword.get(opts, :fail_on_warn, false)
    skip_tag = Keyword.get(opts, :skip_tag, "livebook:test skip")

    files =
      patterns
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> maybe_filter(filter_pattern)

    if files == [] do
      Mix.shell().info("No .livemd files found (patterns: #{Enum.join(patterns, ", ")})")
      System.halt(0)
    end

    Mix.shell().info(
      "Running #{length(files)} livebook(s) with max_concurrency=#{max_conc} timeout=#{timeout_sec}s"
    )

    results =
      files
      |> Task.async_stream(
        fn path -> run_one(path, timeout_sec, fail_on_warn?, skip_tag) end,
        max_concurrency: max_conc,
        timeout: (timeout_sec + 30) * 1_000,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, res} ->
          res

        {:exit, reason} ->
          {:error, %{path: "unknown", status: :task_exit, output: inspect(reason)}}
      end)

    Enum.each(results, &print_result/1)

    failures = Enum.filter(results, &match?({:error, _}, &1))

    if failures != [] do
      Mix.raise("#{length(failures)}/#{length(results)} livebook(s) failed")
    end
  end

  defp maybe_filter(files, nil), do: files
  defp maybe_filter(files, pat), do: Enum.filter(files, &String.contains?(&1, pat))

  defp run_one(path, _timeout_sec, fail_on_warn?, skip_tag) do
    livemd = File.read!(path)

    if skip_entire_notebook?(livemd, skip_tag) do
      {:ok, %{path: path, skipped: true}}
    else
      script = __MODULE__.LivemdExtract.to_elixir_script(livemd)

      if blank?(script) do
        {:error,
         %{path: path, status: :no_elixir_blocks, output: "No ```elixir code fences found"}}
      else
        tmp = tmp_script_path(path)
        File.write!(tmp, script)

        {output, status} =
          System.cmd("elixir", [tmp],
            env: child_env(),
            stderr_to_stdout: true,
            into: ""
          )

        cond do
          status == 0 and fail_on_warn? and has_warning?(output) ->
            {:error, %{path: path, status: :warnings, output: output}}

          status == 0 ->
            {:ok, %{path: path, skipped: false}}

          true ->
            {:error, %{path: path, status: status, output: output}}
        end
      end
    end
  rescue
    e ->
      {:error,
       %{path: path, status: :exception, output: Exception.format(:error, e, __STACKTRACE__)}}
  end

  defp print_result({:ok, %{path: path, skipped: true}}),
    do: Mix.shell().info("⏭️  SKIP  #{path}")

  defp print_result({:ok, %{path: path}}),
    do: Mix.shell().info("✅ PASS  #{path}")

  defp print_result({:error, %{path: path, status: status, output: out}}) do
    Mix.shell().error("❌ FAIL  #{path} (#{inspect(status)})\n#{truncate(out)}\n")
  end

  defp truncate(s) when is_binary(s) do
    max = 12_000
    if byte_size(s) > max, do: binary_part(s, 0, max) <> "\n…(truncated)", else: s
  end

  defp tmp_script_path(path) do
    hash = :erlang.phash2(path)
    Path.join(System.tmp_dir!(), "livemd_test_#{hash}.exs")
  end

  defp child_env do
    # Provide MIX_ENV and preserve current environment
    [{"MIX_ENV", to_string(Mix.env())} | System.get_env() |> Enum.to_list()]
  end

  defp has_warning?(output) do
    # Simple heuristic: adjust if you want stricter matching
    String.contains?(output, "warning:")
  end

  defp blank?(s), do: String.trim(s) == ""

  defp skip_entire_notebook?(livemd, tag) when is_binary(tag) do
    # Convention: if a notebook contains this marker anywhere, skip the whole thing
    # Example in the .livemd:
    #   <!-- livebook:test skip -->
    String.contains?(livemd, "<!-- #{tag} -->") or String.contains?(livemd, "# #{tag}")
  end

  defmodule LivemdExtract do
    @moduledoc false

    # Matches:
    # ```elixir
    # code...
    # ```
    @elixir_fence ~r/```elixir\s*\n(.*?)```/ms

    def to_elixir_script(livemd) when is_binary(livemd) do
      @elixir_fence
      |> Regex.scan(livemd, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.join("\n\n")
      |> then(&wrap_header/1)
    end

    defp wrap_header(body) do
      # Replace path-based Mix.install with absolute path to project root
      project_root = File.cwd!()

      body_fixed =
        String.replace(
          body,
          ~r/path: Path\.join\(__DIR__, "\.\.\/\.\."\)/,
          "path: \"#{project_root}\""
        )

      """
      # Generated from .livemd by mix livebook.test
      # NOTE: Only ```elixir fenced blocks are executed.
      #
      #{body_fixed}
      """
    end
  end
end
