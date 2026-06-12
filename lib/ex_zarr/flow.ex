if Code.ensure_loaded?(Flow) do
  defmodule ExZarr.Flow do
    @moduledoc """
    Flow integration for parallel, backpressure-aware Zarr chunk processing.

    Flow partitions chunk streams across schedulers and applies backpressure
    automatically. Use this when processing very large arrays where you need
    controlled parallelism beyond `Task.async_stream/3`.

    Flow is an optional dependency. Add it to your `mix.exs`:

        {:flow, "~> 1.2"}

    ## Examples

        array
        |> ExZarr.Flow.chunk_flow()
        |> Flow.map(fn {index, data} -> {index, byte_size(data)} end)
        |> Enum.to_list()

        array
        |> ExZarr.Flow.chunk_flow(stages: 8, ordered: false)
        |> Flow.filter(fn {_index, data} -> byte_size(data) > 0 end)
        |> Enum.sum()

    ## Partitioning

    Flow uses `Flow.from_enumerable/2` with `stages: schedulers` by default.
    Chunk reads use `concurrency: 1` because Flow stages provide parallelism.
    Tune throughput with `:stages`, not `:concurrency`.
    """

    alias ExZarr.Array

    @doc """
    Creates a Flow from an array's chunks.

    ## Options

      * `:stages` - Number of Flow stages (default: `System.schedulers_online/0`)
      * Other `stream_chunks/2` options (`:ordered`, `:metadata`, `:filter`, etc.)
        except `:concurrency`, which is fixed at 1 for Flow pipelines

    ## Examples

        array
        |> ExZarr.Flow.chunk_flow(stages: 4)
        |> Flow.map(&process_chunk/1)
        |> Flow.reduce(fn -> 0 end, fn {_i, data}, acc -> acc + byte_size(data) end)
        |> Flow.emit(:state)
        |> Enum.to_list()
    """
    @spec chunk_flow(Array.t(), keyword()) :: Flow.t()
    def chunk_flow(array, opts \\ []) do
      stages = Keyword.get(opts, :stages, System.schedulers_online())
      stream_opts = Keyword.delete(opts, :stages)

      array
      |> Array.stream_chunks(Keyword.put(stream_opts, :concurrency, 1))
      |> Flow.from_enumerable(stages: stages)
    end

    @doc """
    Creates a Flow from array slices along a dimension.

    Chunk reads use `concurrency: 1`; tune parallelism with `:stages`.

    ## Examples

        array
        |> ExZarr.Flow.slice_flow(0, stages: 4)
        |> Flow.map(fn {_start, data} -> byte_size(data) end)
        |> Enum.to_list()
    """
    @spec slice_flow(Array.t(), non_neg_integer(), keyword()) :: Flow.t()
    def slice_flow(array, along, opts \\ []) do
      stages = Keyword.get(opts, :stages, System.schedulers_online())
      stream_opts = Keyword.delete(opts, :stages)

      array
      |> Array.stream_slices(along, Keyword.put(stream_opts, :concurrency, 1))
      |> Flow.from_enumerable(stages: stages)
    end
  end
else
  defmodule ExZarr.Flow do
    @moduledoc """
    Flow integration for Zarr chunk processing.

    Flow is an optional dependency. Add `{:flow, "~> 1.2"}` to your deps.
    """

    @doc false
    def chunk_flow(_array, _opts \\ []) do
      raise ArgumentError, "Flow is required. Add {:flow, \"~> 1.2\"} to your deps."
    end

    @doc false
    def slice_flow(_array, _along, _opts \\ []) do
      raise ArgumentError, "Flow is required. Add {:flow, \"~> 1.2\"} to your deps."
    end
  end
end
