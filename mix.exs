defmodule ExZarr.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/thanos/ExZarr"

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
      {:zigler, "~> 0.13", runtime: false},

      # Cloud storage backends (optional)
      {:ex_aws, "~> 2.5", optional: true},
      {:ex_aws_s3, "~> 2.5", optional: true},
      {:sweet_xml, "~> 0.7", optional: true},
      {:goth, "~> 1.4", optional: true},
      {:google_api_storage, "~> 0.36", optional: true},
      {:azurex, "~> 1.1"},
      {:req, "~> 0.4", optional: true},

      # Database storage backends (optional)
      {:mongodb_driver, "~> 1.4", optional: true},

      # Observability
      {:telemetry, "~> 1.2"},

      # Numerical computing (optional)
      {:nx, "~> 0.7", optional: true},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ] ++
      [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.18", only: :test},
        {:stream_data, "~> 1.1", only: [:dev, :test]},
        {:mox, "~> 1.1", only: :test},
        {:benchee, "~> 1.3", only: :dev},
        {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
      ]
  end

  defp description do
    """
    Pure Elixir implementation of Zarr v2 and v3: compressed, chunked, N-dimensional arrays
    with full Python zarr-python compatibility. Supports chunk streaming, custom encoders,
    and multiple storage backends including S3 and GCS.
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
        # Getting Started
        "README.md",
        "ZARR_V3_STATUS.md",
        "guides/quickstart.md",

        # Core Concepts
        "guides/core_concepts.md",
        "guides/parallel_io.md",

        # Storage and Backends
        "guides/storage_providers.md",
        "guides/custom_storage_backend.md",

        # Compression and Data Processing
        "guides/compression_codecs.md",
        "guides/python_interop.md",

        # Advanced Topics
        "guides/performance.md",
        "guides/nx_integration.md",

        # Reference
        "guides/troubleshooting.md",
        "guides/glossary.md",

        # Contributing
        "guides/contributing.md",

        # Additional Documentation
        "CHANGELOG.md",
        "INTEROPERABILITY.md",
        "PERFORMANCE_IMPROVEMENTS.md",
        "SECURITY.md",
        "docs/V2_TO_V3_MIGRATION.md",
        "benchmarks/README.md"
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "guides/quickstart.md"
        ],
        "Core Concepts": [
          "guides/core_concepts.md",
          "guides/parallel_io.md"
        ],
        "Storage and Backends": [
          "guides/storage_providers.md",
          "guides/custom_storage_backend.md"
        ],
        "Compression and Data Processing": [
          "guides/compression_codecs.md",
          "guides/python_interop.md"
        ],
        "Advanced Topics": [
          "guides/performance.md",
          "guides/nx_integration.md"
        ],
        Reference: [
          "guides/troubleshooting.md",
          "guides/glossary.md"
        ],
        Contributing: [
          "guides/contributing.md"
        ],
        "Additional Documentation": [
          "CHANGELOG.md",
          "INTEROPERABILITY.md",
          "PERFORMANCE_IMPROVEMENTS.md",
          "SECURITY.md",
          "docs/V2_TO_V3_MIGRATION.md",
          "benchmarks/README.md"
        ]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Thanos Vassilakis"],
      logo: nil,
      api_reference: true,
      formatters: ["html"],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Add search and navigation enhancements
  defp before_closing_body_tag(:html) do
    """
    <script>
      // Add keyboard shortcuts for documentation navigation
      document.addEventListener('keydown', function(e) {
        // Press 'g' then 'h' to go to guides home
        if (e.key === 'g') {
          setTimeout(function() {
            document.addEventListener('keydown', function handler(e2) {
              if (e2.key === 'h') {
                window.location.href = 'readme.html';
              }
              document.removeEventListener('keydown', handler);
            }, {once: true});
          }, 100);
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
