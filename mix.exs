defmodule ExZarr.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-username/ex_zarr"

  def project do
    [
      app: :ex_zarr,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Package info
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExZarr",
      source_url: @source_url,

      # Testing
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [:underspecs, :unmatched_returns],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  defp deps do
    [
      # Ziggler for Zig NIFs (compression codecs)
      {:zigler, "~> 0.13", runtime: false},
      # JSON encoding/decoding for metadata
      {:jason, "~> 1.4"},
      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ] ++
      [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.18", only: :test}
      ]
  end

  defp description do
    """
    Elixir implementation of Zarr: compressed, chunked, N-dimensional arrays
    for parallel computing. Includes Zig-based compression codecs for high performance.
    """
  end

  defp package do
    [
      name: "ex_zarr",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Zarr Specification" => "https://zarr.dev"
      },
      maintainers: ["Thanos Vassilakis"],
      files: ~w(lib priv native .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExZarr",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
