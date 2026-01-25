defmodule ExZarr.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/thanos/ex_zarr"

  def project do
    [
      app: :ex_zarr,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      aliases: aliases(),

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

  defp aliases do
    [
      compile: ["compile", "fix_nif_rpaths"]
    ]
  end

  def application do
    [
      mod: {ExZarr.Application, []},
      extra_applications: [:logger, :crypto, :mnesia]
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
      # JSON encoding/decoding for metadata
      {:jason, "~> 1.4"},

      # Zig NIFs for compression codecs
      {:zigler, "~> 0.13.0", runtime: false},

      # Cloud storage backends (optional)
      {:ex_aws, "~> 2.5", optional: true},
      {:ex_aws_s3, "~> 2.5", optional: true},
      {:azurex, "~> 1.1"},
      {:goth, "~> 1.4", optional: true},
      {:req, "~> 0.4", optional: true},

      # Database storage backends (optional)
      {:mongodb_driver, "~> 1.4", optional: true},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ] ++
      [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.18", only: :test},
        {:stream_data, "~> 1.1", only: [:dev, :test]},
        {:mox, "~> 1.1", only: :test}
      ]
  end

  defp description do
    """
    Pure Elixir implementation of Zarr v2: compressed, chunked, N-dimensional arrays
    with full Python zarr-python compatibility. Perfect for data science, scientific
    computing, and working with large datasets.
    """
  end

  defp package do
    [
      name: "ex_zarr",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Zarr Specification" => "https://zarr.dev"
      },
      maintainers: ["Thanos Vassilakis"],
      files:
        ~w(lib priv native .formatter.exs mix.exs README.md CHANGELOG.md INTEROPERABILITY.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExZarr",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "INTEROPERABILITY.md"
      ],
      groups_for_extras: [
        Guides: ~r/INTEROPERABILITY/,
        "Release Notes": ~r/CHANGELOG/
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Thanos Vassilakis"]
    ]
  end
end
