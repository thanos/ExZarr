defmodule ExZarr.Gallery.SampleData do
  @moduledoc """
  Deterministic sample data generators used by the Livebook tutorials.
  """

  @doc """
  Creates a `rows x cols` matrix (flat list) with a simple pattern.

  Value at (r, c) is: `r * 1000 + c`.
  """
  @spec matrix(non_neg_integer(), non_neg_integer()) :: [number()]
  def matrix(rows, cols) when rows >= 0 and cols >= 0 do
    for r <- 0..(rows - 1),
        c <- 0..(cols - 1) do
      r * 1000 + c
    end
  end

  @doc """
  Returns `n` pseudo-random floats in [0,1) with a stable seed.
  """
  @spec rand_floats(pos_integer(), integer()) :: [float()]
  def rand_floats(n, seed \\ 42) when n > 0 do
    _ = :rand.seed(:exsss, {seed, seed, seed})
    for _ <- 1..n, do: :rand.uniform()
  end

  @doc """
  Builds a tiny corpus for embedding demos (no network calls).
  """
  @spec tiny_corpus() :: [{String.t(), String.t()}]
  def tiny_corpus do
    [
      {"doc-001", "zarr stores chunked n-dimensional arrays in a key value store"},
      {"doc-002", "elixir otp is great for concurrency fault tolerance and supervision"},
      {"doc-003", "finance tick data is time series with microstructure noise"},
      {"doc-004", "crypto markets trade 24 7 with high volatility and fragmented venues"},
      {"doc-005", "embeddings map text into vectors enabling similarity search"}
    ]
  end
end
