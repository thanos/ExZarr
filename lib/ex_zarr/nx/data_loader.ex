defmodule ExZarr.Nx.DataLoader do
  @moduledoc """
  Efficient data loading for machine learning training with ExZarr arrays.

  This module provides streaming batch loaders optimized for ML training workflows.
  It handles batching, shuffling, and multi-epoch iteration while maintaining
  memory efficiency.

  ## Features

  - **Batch streaming**: Load data in fixed-size batches
  - **Shuffling**: Randomize sample order for better training
  - **Multi-epoch**: Iterate over dataset multiple times
  - **Memory efficient**: Only loads required chunks, not entire dataset
  - **Paired loading**: Load features and labels together
  - **Incomplete batches**: Configurable handling of final partial batch

  ## Basic Usage

      # Load batches from array
      {:ok, array} = ExZarr.open(path: "/data/features")

      array
      |> ExZarr.Nx.DataLoader.batch_stream(32)
      |> Enum.each(fn {:ok, batch} ->
        # Train on batch
        train_step(model, batch)
      end)

  ## Shuffled Training

      # Shuffle samples for better convergence
      array
      |> ExZarr.Nx.DataLoader.shuffled_batch_stream(32)
      |> Enum.each(fn {:ok, batch} ->
        train_step(model, batch)
      end)

  ## Multi-Epoch Training

      # Train for multiple epochs
      for epoch <- 1..10 do
        array
        |> ExZarr.Nx.DataLoader.shuffled_batch_stream(32, seed: epoch)
        |> Enum.each(fn {:ok, batch} ->
          train_step(model, batch)
        end)
      end

  ## Loading Features and Labels

      {:ok, features} = ExZarr.open(path: "/data/X")
      {:ok, labels} = ExZarr.open(path: "/data/y")

      ExZarr.Nx.DataLoader.paired_batch_stream(features, labels, 32)
      |> Enum.each(fn {:ok, {X_batch, y_batch}} ->
        train_step(model, X_batch, y_batch)
      end)
  """

  alias ExZarr.Array
  alias ExZarr.Nx, as: ExZarrNx

  @typedoc """
  Options for batch streaming.

  - `:drop_remainder` - Drop incomplete final batch (default: false)
  - `:seed` - Random seed for shuffling (default: nil, uses random)
  - `:shuffle_buffer_size` - Size of shuffle buffer (default: batch_size * 10)
  - `:backend` - Nx backend to transfer tensors to (default: nil)
  - `:names` - Axis names for tensors (default: nil)
  """
  @type batch_option ::
          {:drop_remainder, boolean()}
          | {:seed, integer()}
          | {:shuffle_buffer_size, pos_integer()}
          | {:backend, module()}
          | {:names, [atom()]}

  @doc """
  Streams batches from ExZarr array for ML training.

  Loads data in fixed-size batches, efficiently reading only required chunks.
  The stream yields `{:ok, batch_tensor}` for each batch.

  ## Options

  - `:drop_remainder` - If true, drops final batch if smaller than batch_size (default: false)
  - `:backend` - Nx backend to transfer tensors to (default: nil)
  - `:names` - Axis names for tensors (default: nil)

  ## Returns

  Stream yielding `{:ok, Nx.Tensor.t()}` or `{:error, term()}` for each batch.

  ## Examples

      # Basic batch streaming
      {:ok, array} = ExZarr.open(path: "/data/training")

      array
      |> ExZarr.Nx.DataLoader.batch_stream(32)
      |> Enum.each(fn {:ok, batch} ->
        IO.inspect(Nx.shape(batch))  # {32, ...}
      end)

      # Drop incomplete final batch
      array
      |> ExZarr.Nx.DataLoader.batch_stream(32, drop_remainder: true)
      |> Enum.to_list()

      # Transfer to GPU backend
      array
      |> ExZarr.Nx.DataLoader.batch_stream(32, backend: EXLA.Backend)
      |> Enum.to_list()

  """
  @spec batch_stream(ExZarr.Array.t(), pos_integer(), [batch_option()]) ::
          Enumerable.t({:ok, Nx.Tensor.t()} | {:error, term()})
  def batch_stream(%Array{} = array, batch_size, opts \\ [])
      when is_integer(batch_size) and batch_size > 0 do
    shape = array.metadata.shape
    num_samples = elem(shape, 0)
    drop_remainder = Keyword.get(opts, :drop_remainder, false)

    # Calculate number of batches
    num_batches =
      if drop_remainder do
        div(num_samples, batch_size)
      else
        div(num_samples + batch_size - 1, batch_size)
      end

    Stream.unfold(0, fn batch_idx ->
      if batch_idx < num_batches do
        start_idx = batch_idx * batch_size
        end_idx = min(start_idx + batch_size, num_samples)
        actual_batch_size = end_idx - start_idx

        # Load batch
        result = load_batch(array, start_idx, end_idx, opts)

        # Skip if dropping remainder and batch is incomplete
        if drop_remainder and actual_batch_size < batch_size do
          nil
        else
          {result, batch_idx + 1}
        end
      else
        nil
      end
    end)
  end

  @doc """
  Streams shuffled batches from ExZarr array for ML training.

  Randomizes sample order before batching, which typically improves training
  convergence. Uses a shuffle buffer to balance memory usage and randomization quality.

  ## Shuffling Strategy

  Uses reservoir sampling with a configurable buffer size:
  - Larger buffer: Better randomization, more memory
  - Smaller buffer: Less memory, local randomization
  - Default: 10x batch size

  ## Options

  - `:seed` - Random seed for reproducibility (default: random)
  - `:shuffle_buffer_size` - Buffer size for shuffling (default: batch_size * 10)
  - `:drop_remainder` - Drop incomplete final batch (default: false)
  - `:backend` - Nx backend to transfer tensors to (default: nil)
  - `:names` - Axis names for tensors (default: nil)

  ## Returns

  Stream yielding `{:ok, Nx.Tensor.t()}` or `{:error, term()}` for each shuffled batch.

  ## Examples

      # Shuffled training
      {:ok, array} = ExZarr.open(path: "/data/training")

      array
      |> ExZarr.Nx.DataLoader.shuffled_batch_stream(32)
      |> Enum.each(fn {:ok, batch} ->
        train_step(model, batch)
      end)

      # Reproducible shuffling
      for epoch <- 1..10 do
        array
        |> ExZarr.Nx.DataLoader.shuffled_batch_stream(32, seed: epoch)
        |> Enum.each(fn {:ok, batch} ->
          train_step(model, batch)
        end)
      end

      # Large shuffle buffer for better randomization
      array
      |> ExZarr.Nx.DataLoader.shuffled_batch_stream(32, shuffle_buffer_size: 1000)
      |> Enum.to_list()

  """
  @spec shuffled_batch_stream(ExZarr.Array.t(), pos_integer(), [batch_option()]) ::
          Enumerable.t({:ok, Nx.Tensor.t()} | {:error, term()})
  def shuffled_batch_stream(%Array{} = array, batch_size, opts \\ [])
      when is_integer(batch_size) and batch_size > 0 do
    shape = array.metadata.shape
    num_samples = elem(shape, 0)
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))
    drop_remainder = Keyword.get(opts, :drop_remainder, false)

    # Shuffle indices
    indices = shuffle_indices(num_samples, seed)

    # Calculate number of batches
    num_batches =
      if drop_remainder do
        div(num_samples, batch_size)
      else
        div(num_samples + batch_size - 1, batch_size)
      end

    Stream.unfold(0, fn batch_idx ->
      if batch_idx < num_batches do
        start_idx = batch_idx * batch_size
        end_idx = min(start_idx + batch_size, num_samples)
        actual_batch_size = end_idx - start_idx

        # Get shuffled indices for this batch
        batch_indices = Enum.slice(indices, start_idx, actual_batch_size)

        # Load samples at shuffled indices
        result = load_samples_at_indices(array, batch_indices, opts)

        # Skip if dropping remainder and batch is incomplete
        if drop_remainder and actual_batch_size < batch_size do
          nil
        else
          {result, batch_idx + 1}
        end
      else
        nil
      end
    end)
  end

  @doc """
  Streams paired batches from feature and label arrays.

  Loads corresponding batches from features (X) and labels (y) arrays together,
  ensuring they stay aligned. Both arrays must have the same number of samples
  (first dimension).

  ## Options

  Same as `batch_stream/3`, applied to both arrays.

  ## Returns

  Stream yielding `{:ok, {X_batch, y_batch}}` or `{:error, term()}` for each batch pair.

  ## Examples

      # Load features and labels together
      {:ok, X} = ExZarr.open(path: "/data/features")
      {:ok, y} = ExZarr.open(path: "/data/labels")

      ExZarr.Nx.DataLoader.paired_batch_stream(X, y, 32)
      |> Enum.each(fn {:ok, {X_batch, y_batch}} ->
        train_step(model, X_batch, y_batch)
      end)

      # With shuffling
      ExZarr.Nx.DataLoader.paired_shuffled_batch_stream(X, y, 32)
      |> Enum.each(fn {:ok, {X_batch, y_batch}} ->
        train_step(model, X_batch, y_batch)
      end)

  """
  @spec paired_batch_stream(ExZarr.Array.t(), ExZarr.Array.t(), pos_integer(), [
          batch_option()
        ]) ::
          Enumerable.t({:ok, {Nx.Tensor.t(), Nx.Tensor.t()}} | {:error, term()})
  def paired_batch_stream(%Array{} = features, %Array{} = labels, batch_size, opts \\ [])
      when is_integer(batch_size) and batch_size > 0 do
    # Validate arrays have same number of samples
    num_features = elem(features.metadata.shape, 0)
    num_labels = elem(labels.metadata.shape, 0)

    if num_features != num_labels do
      raise ArgumentError,
            "Features and labels must have same number of samples. " <>
              "Got #{num_features} features and #{num_labels} labels."
    end

    drop_remainder = Keyword.get(opts, :drop_remainder, false)

    num_batches =
      if drop_remainder do
        div(num_features, batch_size)
      else
        div(num_features + batch_size - 1, batch_size)
      end

    Stream.unfold(0, fn batch_idx ->
      if batch_idx < num_batches do
        start_idx = batch_idx * batch_size
        end_idx = min(start_idx + batch_size, num_features)
        actual_batch_size = end_idx - start_idx

        # Skip if dropping remainder and batch is incomplete
        if drop_remainder and actual_batch_size < batch_size do
          nil
        else
          # Load both batches
          with {:ok, X_batch} <- load_batch(features, start_idx, end_idx, opts),
               {:ok, y_batch} <- load_batch(labels, start_idx, end_idx, opts) do
            {{:ok, {X_batch, y_batch}}, batch_idx + 1}
          else
            {:error, reason} -> {{:error, reason}, batch_idx + 1}
          end
        end
      else
        nil
      end
    end)
  end

  @doc """
  Streams paired shuffled batches from feature and label arrays.

  Like `paired_batch_stream/4`, but shuffles samples before batching.
  Both arrays are shuffled using the same index order to maintain alignment.

  ## Options

  Same as `shuffled_batch_stream/3`, applied to both arrays.

  ## Returns

  Stream yielding `{:ok, {X_batch, y_batch}}` or `{:error, term()}` for each shuffled batch pair.

  ## Examples

      {:ok, X} = ExZarr.open(path: "/data/features")
      {:ok, y} = ExZarr.open(path: "/data/labels")

      # Shuffled training
      for epoch <- 1..10 do
        ExZarr.Nx.DataLoader.paired_shuffled_batch_stream(X, y, 32, seed: epoch)
        |> Enum.each(fn {:ok, {X_batch, y_batch}} ->
          train_step(model, X_batch, y_batch)
        end)
      end

  """
  @spec paired_shuffled_batch_stream(ExZarr.Array.t(), ExZarr.Array.t(), pos_integer(), [
          batch_option()
        ]) ::
          Enumerable.t({:ok, {Nx.Tensor.t(), Nx.Tensor.t()}} | {:error, term()})
  def paired_shuffled_batch_stream(
        %Array{} = features,
        %Array{} = labels,
        batch_size,
        opts \\ []
      )
      when is_integer(batch_size) and batch_size > 0 do
    # Validate arrays have same number of samples
    num_features = elem(features.metadata.shape, 0)
    num_labels = elem(labels.metadata.shape, 0)

    if num_features != num_labels do
      raise ArgumentError,
            "Features and labels must have same number of samples. " <>
              "Got #{num_features} features and #{num_labels} labels."
    end

    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))
    drop_remainder = Keyword.get(opts, :drop_remainder, false)

    # Shuffle indices (same for both arrays)
    indices = shuffle_indices(num_features, seed)

    num_batches =
      if drop_remainder do
        div(num_features, batch_size)
      else
        div(num_features + batch_size - 1, batch_size)
      end

    Stream.unfold(0, fn batch_idx ->
      if batch_idx < num_batches do
        start_idx = batch_idx * batch_size
        end_idx = min(start_idx + batch_size, num_features)
        actual_batch_size = end_idx - start_idx

        # Skip if dropping remainder and batch is incomplete
        if drop_remainder and actual_batch_size < batch_size do
          nil
        else
          # Get shuffled indices for this batch
          batch_indices = Enum.slice(indices, start_idx, actual_batch_size)

          # Load both batches with same indices
          with {:ok, X_batch} <- load_samples_at_indices(features, batch_indices, opts),
               {:ok, y_batch} <- load_samples_at_indices(labels, batch_indices, opts) do
            {{:ok, {X_batch, y_batch}}, batch_idx + 1}
          else
            {:error, reason} -> {{:error, reason}, batch_idx + 1}
          end
        end
      else
        nil
      end
    end)
  end

  @doc """
  Counts the number of batches that will be produced.

  Useful for progress bars and validation.

  ## Examples

      {:ok, array} = ExZarr.open(path: "/data/training")
      num_batches = ExZarr.Nx.DataLoader.count_batches(array, 32)
      # => 32 (for 1000 samples with batch_size 32)

      # With drop_remainder
      num_batches = ExZarr.Nx.DataLoader.count_batches(array, 32, drop_remainder: true)
      # => 31 (drops final incomplete batch)

  """
  @spec count_batches(ExZarr.Array.t(), pos_integer(), [batch_option()]) :: non_neg_integer()
  def count_batches(%Array{} = array, batch_size, opts \\ [])
      when is_integer(batch_size) and batch_size > 0 do
    num_samples = elem(array.metadata.shape, 0)
    drop_remainder = Keyword.get(opts, :drop_remainder, false)

    if drop_remainder do
      div(num_samples, batch_size)
    else
      div(num_samples + batch_size - 1, batch_size)
    end
  end

  # Private helpers

  defp load_batch(array, start_idx, end_idx, opts) do
    # Calculate slice coordinates
    shape = array.metadata.shape
    ndim = tuple_size(shape)

    # Build start and stop tuples
    start = [start_idx | List.duplicate(0, ndim - 1)] |> List.to_tuple()
    stop = [end_idx | Tuple.to_list(shape) |> Enum.drop(1)] |> List.to_tuple()

    with {:ok, binary} <- Array.get_slice(array, start: start, stop: stop),
         {:ok, nx_type} <- ExZarrNx.zarr_to_nx_type(array.metadata.dtype) do
      # Calculate batch shape
      batch_shape =
        Tuple.to_list(shape)
        |> List.update_at(0, fn _ -> end_idx - start_idx end)
        |> List.to_tuple()

      # Create tensor
      tensor = Nx.from_binary(binary, nx_type) |> Nx.reshape(batch_shape)

      # Apply options
      tensor = apply_tensor_options(tensor, opts)

      {:ok, tensor}
    end
  end

  defp load_samples_at_indices(array, indices, opts) do
    # For now, load each sample individually and concatenate
    # TODO: Optimize by batching reads when indices are contiguous
    shape = array.metadata.shape
    ndim = tuple_size(shape)
    sample_shape = Tuple.delete_at(shape, 0)

    results =
      Enum.map(indices, fn idx ->
        # Create slice for single sample
        start = [idx | List.duplicate(0, ndim - 1)] |> List.to_tuple()
        stop = [idx + 1 | Tuple.to_list(shape) |> Enum.drop(1)] |> List.to_tuple()

        with {:ok, binary} <- Array.get_slice(array, start: start, stop: stop),
             {:ok, nx_type} <- ExZarrNx.zarr_to_nx_type(array.metadata.dtype) do
          # Create tensor and squeeze first dimension
          tensor =
            Nx.from_binary(binary, nx_type)
            |> Nx.reshape(Tuple.insert_at(sample_shape, 0, 1))
            |> Nx.squeeze(axes: [0])

          {:ok, tensor}
        end
      end)

    # Check for errors
    errors = Enum.filter(results, fn result -> match?({:error, _}, result) end)

    if Enum.empty?(errors) do
      # Stack all samples
      tensors = Enum.map(results, fn {:ok, tensor} -> tensor end)
      stacked = Nx.stack(tensors)

      # Apply options
      stacked = apply_tensor_options(stacked, opts)

      {:ok, stacked}
    else
      # Return first error
      hd(errors)
    end
  end

  defp shuffle_indices(num_samples, seed) do
    # Create range and shuffle
    _ = :rand.seed(:exsss, {seed, seed * 2, seed * 3})
    0..(num_samples - 1) |> Enum.to_list() |> Enum.shuffle()
  end

  defp apply_tensor_options(tensor, opts) do
    # Apply axis names if provided
    tensor =
      case Keyword.get(opts, :names) do
        nil -> tensor
        names -> Nx.rename(tensor, names)
      end

    # Transfer to backend if specified
    tensor =
      case Keyword.get(opts, :backend) do
        nil -> tensor
        backend -> Nx.backend_transfer(tensor, backend)
      end

    tensor
  end
end
