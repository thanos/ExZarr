if Code.ensure_loaded?(Broadway) do
  defmodule ExZarr.Broadway do
    @moduledoc """
    Broadway integration helpers for fault-tolerant Zarr processing pipelines.

    Broadway is an optional dependency:

        {:broadway, "~> 1.0"}

    See `livebooks/broadway_pipeline.livemd` for a complete example.
    """

    alias ExZarr.Array

    @doc """
    Returns Broadway child spec options for a chunk-processing pipeline.
    """
    @spec chunk_pipeline_options(module(), Array.t(), keyword()) :: keyword()
    def chunk_pipeline_options(module, array, opts \\ []) do
      concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
      max_demand = Keyword.get(opts, :max_demand, 10)
      min_demand = Keyword.get(opts, :min_demand, 5)
      stream_opts = Keyword.get(opts, :stream_opts, [])
      name = Keyword.get(opts, :name, module)

      [
        name: name,
        producer: [
          module: {ExZarr.Broadway.ChunkProducer, array: array, stream_opts: stream_opts},
          concurrency: 1
        ],
        processors: [
          default: [
            concurrency: concurrency,
            max_demand: max_demand,
            min_demand: min_demand
          ]
        ],
        context: %{array: array, module: module}
      ]
    end

    @doc """
    Starts a Broadway pipeline for chunk processing.
    """
    @spec start_chunk_pipeline(module(), Array.t(), keyword()) :: {:ok, pid()} | {:error, term()}
    def start_chunk_pipeline(module, array, opts \\ []) do
      Broadway.start_link(module, chunk_pipeline_options(module, array, opts))
    end
  end
else
  defmodule ExZarr.Broadway do
    @moduledoc """
    Broadway integration for Zarr pipelines.

    Broadway is an optional dependency. Add `{:broadway, "~> 1.0"}` to your deps.
    """

    @doc false
    def chunk_pipeline_options(_module, _array, _opts \\ []) do
      raise ArgumentError, "Broadway is required. Add {:broadway, \"~> 1.0\"} to your deps."
    end

    @doc false
    def start_chunk_pipeline(_module, _array, _opts \\ []) do
      raise ArgumentError, "Broadway is required. Add {:broadway, \"~> 1.0\"} to your deps."
    end
  end
end
