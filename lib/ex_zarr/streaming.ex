defmodule ExZarr.Streaming do
  @moduledoc false

  alias ExZarr.{Array, StreamError, Telemetry}
  alias ExZarr.ChunkGrid.{Irregular, Regular}

  @default_max_concurrency 128

  @type chunk_event :: {tuple(), binary()} | %{index: tuple(), data: binary(), metadata: map()}
  @type slice_event :: {tuple(), binary()} | %{index: tuple(), data: binary(), metadata: map()}

  @doc false
  @spec normalize_stream_opts(keyword()) :: keyword()
  def normalize_stream_opts(opts) do
    concurrency =
      Keyword.get(opts, :concurrency) ||
        Keyword.get(opts, :parallel, 1)

    if Keyword.has_key?(opts, :parallel) and not Keyword.has_key?(opts, :concurrency) do
      require Logger
      Logger.warning(":parallel is deprecated in streaming APIs; use :concurrency instead")
    end

    timeout = Keyword.get(opts, :timeout, 60_000)

    opts
    |> Keyword.put(:concurrency, min(max(concurrency, 1), @default_max_concurrency))
    |> Keyword.put(:timeout, timeout)
  end

  @doc false
  @spec chunk_indices(Array.t(), keyword()) :: [tuple()]
  def chunk_indices(array, opts) do
    include_missing = Keyword.get(opts, :include_missing, false)
    filter = Keyword.get(opts, :filter, nil)

    indices =
      if include_missing do
        all_chunk_indices(array)
      else
        case ExZarr.Storage.list_chunks(array.storage) do
          {:ok, stored} -> stored
          {:error, _} -> []
        end
      end

    if filter do
      Enum.filter(indices, filter)
    else
      indices
    end
  end

  @doc false
  @spec all_chunk_indices(Array.t()) :: [tuple()]
  def all_chunk_indices(%Array{chunk_grid_module: Irregular, chunk_grid_state: state} = _array)
      when not is_nil(state) do
    Irregular.all_chunk_indices(state)
  end

  def all_chunk_indices(%Array{chunk_grid_module: module, chunk_grid_state: state} = array)
      when not is_nil(module) and not is_nil(state) do
    if function_exported?(module, :all_chunk_indices, 1) do
      module.all_chunk_indices(state)
    else
      regular_indices(array)
    end
  end

  def all_chunk_indices(array), do: regular_indices(array)

  @doc false
  @spec regular_indices(Array.t()) :: [tuple()]
  def regular_indices(array) do
    grid = %Regular{chunk_shape: array.chunks, array_shape: array.shape}
    Regular.all_chunk_indices(grid)
  end

  @doc false
  @spec build_chunk_from_read(Array.t(), tuple(), keyword()) :: chunk_event() | nil
  def build_chunk_from_read(array, chunk_index, opts) do
    case Array.__ex_zarr_stream_read_chunk__(array, chunk_index) do
      {:ok, data} -> build_chunk_event(array, chunk_index, data, opts)
      {:error, _} -> nil
    end
  end

  @doc false
  @spec build_chunk_event(Array.t(), tuple(), binary(), keyword()) :: chunk_event()
  def build_chunk_event(array, chunk_index, data, opts) do
    if Keyword.get(opts, :metadata, false) do
      {start_coords, end_coords} = Array.get_chunk_bounds(array, chunk_index)
      chunk_shape = Array.get_chunk_shape(array, chunk_index)

      %{
        index: chunk_index,
        data: data,
        metadata: %{
          bounds: {start_coords, end_coords},
          shape: chunk_shape,
          bytes: byte_size(data)
        }
      }
    else
      {chunk_index, data}
    end
  end

  @doc false
  @spec stream_chunks(Array.t(), keyword(), (Array.t(), tuple() ->
                                               {:ok, binary()} | {:error, term()})) ::
          Enumerable.t()
  def stream_chunks(array, opts, read_fun) do
    opts = normalize_stream_opts(opts)
    on_error = Keyword.get(opts, :on_error, :skip)
    indices = chunk_indices(array, opts)

    stream_events(
      indices,
      :chunks,
      array_ref(array),
      opts,
      fn chunk_index ->
        read_chunk_event(array, chunk_index, opts, read_fun, on_error)
      end,
      opts
    )
  end

  @doc false
  @spec slice_specs(Array.t(), non_neg_integer(), keyword()) :: [{tuple(), tuple()}]
  def slice_specs(array, along, opts) do
    ndim = tuple_size(array.shape)

    if along < 0 or along >= ndim do
      []
    else
      start_coords = slice_start(array, opts)
      stop_coords = slice_stop(array, opts)
      step = Keyword.get(opts, :step, 1)

      dim_size = elem(stop_coords, along) - elem(start_coords, along)

      if dim_size <= 0 or step <= 0 do
        []
      else
        count = div(dim_size + step - 1, step)

        for i <- 0..(count - 1)//1 do
          offset = i * step
          slice_start_coords = put_elem(start_coords, along, elem(start_coords, along) + offset)
          slice_stop_coords = unit_slice_stop(slice_start_coords, stop_coords, along)
          {slice_start_coords, slice_stop_coords}
        end
      end
    end
  end

  defp unit_slice_stop(start_coords, region_stop, along) do
    start_coords
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(region_stop))
    |> Enum.with_index()
    |> Enum.map(fn {{start_val, stop_val}, dim} ->
      if dim == along, do: start_val + 1, else: stop_val
    end)
    |> List.to_tuple()
  end

  @doc false
  @spec stream_slices(
          Array.t(),
          non_neg_integer(),
          keyword(),
          (Array.t(), tuple(), tuple() -> {:ok, binary()} | {:error, term()})
        ) :: Enumerable.t()
  def stream_slices(array, along, opts, read_slice_fun) do
    opts = normalize_stream_opts(opts)
    on_error = Keyword.get(opts, :on_error, :skip)
    specs = slice_specs(array, along, opts)
    telemetry_opts = Keyword.put(opts, :along, along)

    read_slice = fn {slice_start, slice_stop} ->
      case read_slice_fun.(array, slice_start, slice_stop) do
        {:ok, data} ->
          if Keyword.get(opts, :metadata, false) do
            %{
              index: slice_start,
              data: data,
              metadata: %{stop: slice_stop, bytes: byte_size(data)}
            }
          else
            {slice_start, data}
          end

        {:error, reason} ->
          handle_slice_error(on_error, slice_start, reason)
      end
    end

    stream_events(specs, :slices, array_ref(array), telemetry_opts, read_slice, opts)
  end

  defp stream_events(items, type, array_ref, telemetry_opts, read_fun, opts) do
    concurrency = Keyword.fetch!(opts, :concurrency)
    ordered = Keyword.get(opts, :ordered, true)
    timeout = Keyword.fetch!(opts, :timeout)
    progress_callback = Keyword.get(opts, :progress_callback, nil)
    on_error = Keyword.get(opts, :on_error, :skip)
    total = length(items)
    start_time = System.monotonic_time()

    Telemetry.stream_start(array_ref, type, telemetry_opts)

    if concurrency > 1 do
      items
      |> concurrent_event_stream(read_fun,
        concurrency: concurrency,
        ordered: ordered,
        timeout: timeout,
        progress_callback: progress_callback,
        total: total,
        on_error: on_error
      )
      |> with_stream_stop(array_ref, type, start_time)
    else
      sequential_event_stream(
        items,
        read_fun,
        progress_callback,
        total,
        array_ref,
        type,
        start_time
      )
    end
  end

  defp sequential_event_stream(
         items,
         read_fun,
         progress_callback,
         total,
         array_ref,
         type,
         start_time
       ) do
    Stream.resource(
      fn -> {items, 0, start_time} end,
      fn
        {[], done, _start} ->
          {:halt, {[], done, start_time}}

        {[item | rest], done, stream_start} ->
          case read_fun.(item) do
            nil ->
              {[], {rest, done, stream_start}}

            event ->
              new_done = done + 1
              notify_progress(progress_callback, new_done, total)
              {[event], {rest, new_done, stream_start}}
          end
      end,
      fn {_rest, done, stream_start} ->
        Telemetry.stream_stop(array_ref, type, done, stream_start)
      end
    )
  end

  @doc false
  @spec write_stream(Array.t(), Enumerable.t(), keyword(), function()) ::
          {:ok, map()} | {:error, term()}
  def write_stream(array, stream, opts, write_chunk_fun) do
    batch_size = Keyword.get(opts, :batch_size, 1)
    validate = Keyword.get(opts, :validate, true)
    checkpoint = Keyword.get(opts, :checkpoint, nil)
    on_error = Keyword.get(opts, :on_error, :halt)
    array_ref = array_ref(array)
    start_time = System.monotonic_time()

    Telemetry.stream_start(array_ref, :write, opts)

    result =
      stream
      |> Stream.map(&validate_write_entry/1)
      |> Stream.chunk_every(batch_size)
      |> Enum.reduce_while(
        %{written: 0, failed: 0, last_index: nil},
        fn batch, acc ->
          case process_write_batch(array, batch, validate, write_chunk_fun, on_error) do
            {:ok, batch_stats} ->
              new_acc = %{
                written: acc.written + batch_stats.written,
                failed: acc.failed + batch_stats.failed,
                last_index: batch_stats.last_index || acc.last_index
              }

              if checkpoint, do: checkpoint.(new_acc)
              {:cont, new_acc}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )

    case result do
      {:error, reason} ->
        {:error, reason}

      stats ->
        Telemetry.stream_stop(array_ref, :write, stats.written, start_time)
        {:ok, stats}
    end
  end

  defp concurrent_event_stream(items, read_fun, opts) do
    concurrency = Keyword.fetch!(opts, :concurrency)
    ordered = Keyword.fetch!(opts, :ordered)
    timeout = Keyword.fetch!(opts, :timeout)
    progress_callback = Keyword.get(opts, :progress_callback)
    total = Keyword.get(opts, :total, 0)
    on_error = Keyword.get(opts, :on_error, :skip)

    items
    |> Task.async_stream(read_fun,
      max_concurrency: concurrency,
      ordered: ordered,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Stream.with_index(1)
    |> Stream.map(fn
      {{:ok, result}, index} ->
        notify_progress(progress_callback, index, total)
        result

      {{:exit, reason}, index} ->
        notify_progress(progress_callback, index, total)
        handle_async_error(on_error, index, reason)
    end)
    |> Stream.reject(&is_nil/1)
  end

  defp with_stream_stop(stream, array_ref, type, start_time) do
    stream
    |> Stream.map(&{:event, &1})
    |> Stream.concat([{:stop, nil}])
    |> Stream.transform(0, fn
      {:stop, _}, count ->
        Telemetry.stream_stop(array_ref, type, count, start_time)
        {:halt, count}

      {:event, event}, count ->
        {[event], count + 1}
    end)
  end

  defp process_write_batch(array, batch, validate, write_chunk_fun, on_error) do
    Enum.reduce_while(batch, %{written: 0, failed: 0, last_index: nil}, fn item, acc ->
      case item do
        {:error, reason} ->
          handle_write_error(on_error, nil, reason, acc)

        {:ok, entry} ->
          with :ok <- maybe_validate_chunk(array, entry, validate),
               :ok <- write_chunk_fun.(array, entry.index, entry.data) do
            {:cont,
             %{
               written: acc.written + 1,
               failed: acc.failed,
               last_index: entry.index
             }}
          else
            {:error, reason} ->
              handle_write_error(on_error, entry.index, reason, acc)
          end
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      stats -> {:ok, stats}
    end
  end

  defp handle_write_error(:halt, _index, reason, _acc), do: {:halt, {:error, reason}}

  defp handle_write_error(:skip, _index, _reason, acc),
    do: {:cont, %{acc | failed: acc.failed + 1}}

  defp handle_write_error(fun, index, reason, acc) when is_function(fun, 2) do
    fun.(index, reason)
    {:cont, %{acc | failed: acc.failed + 1}}
  end

  defp maybe_validate_chunk(array, entry, true) do
    expected = expected_chunk_bytes(array, entry.index)

    if byte_size(entry.data) == expected do
      :ok
    else
      {:error,
       {:invalid_chunk_size,
        %{index: entry.index, expected: expected, actual: byte_size(entry.data)}}}
    end
  end

  defp maybe_validate_chunk(_array, _entry, false), do: :ok

  defp expected_chunk_bytes(array, chunk_index) do
    shape = Array.get_chunk_shape(array, chunk_index)
    element_size = Array.itemsize(array)
    Enum.reduce(Tuple.to_list(shape), 1, &*/2) * element_size
  end

  defp validate_write_entry({index, data}) when is_tuple(index) and is_binary(data) do
    {:ok, %{index: index, data: data}}
  end

  defp validate_write_entry(%{index: index, data: data})
       when is_tuple(index) and is_binary(data) do
    {:ok, %{index: index, data: data}}
  end

  defp validate_write_entry(entry), do: {:error, {:invalid_entry, entry}}

  defp read_chunk_event(array, chunk_index, opts, read_fun, on_error) do
    array_ref = array_ref(array)

    Telemetry.chunk_read(array_ref, chunk_index, fn ->
      case read_fun.(array, chunk_index) do
        {:ok, data} ->
          build_chunk_event(array, chunk_index, data, opts)

        {:error, reason} ->
          handle_chunk_error(on_error, chunk_index, reason)
      end
    end)
  end

  defp handle_chunk_error(:skip, _index, _reason), do: nil

  defp handle_chunk_error(fun, index, reason) when is_function(fun, 2) do
    fun.(index, reason)
    nil
  end

  defp handle_chunk_error(:halt, index, reason) do
    raise StreamError, index: index, reason: reason
  end

  defp handle_slice_error(:skip, _index, _reason), do: nil

  defp handle_slice_error(fun, index, reason) when is_function(fun, 2) do
    fun.(index, reason)
    nil
  end

  defp handle_slice_error(:halt, index, reason) do
    raise StreamError, index: index, reason: reason
  end

  defp handle_async_error(:skip, _index, _reason), do: nil

  defp handle_async_error(fun, index, reason) when is_function(fun, 2) do
    fun.(index, reason)
    nil
  end

  defp handle_async_error(:halt, index, reason) do
    raise StreamError, index: index, reason: reason
  end

  defp slice_start(array, opts) do
    Keyword.get(opts, :start, zero_tuple(tuple_size(array.shape)))
  end

  defp slice_stop(array, opts) do
    Keyword.get(opts, :stop, array.shape)
  end

  defp zero_tuple(n) do
    List.duplicate(0, n) |> List.to_tuple()
  end

  defp notify_progress(callback, done, total) when is_function(callback, 2) do
    callback.(done, total)
  end

  defp notify_progress(_callback, _done, _total), do: :ok

  defp array_ref(array) do
    {array.shape, array.chunks, array.dtype}
  end
end
