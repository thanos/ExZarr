# ExZarr 101: Cloud‑native arrays in Elixir with Zarr v2

Zarr is a storage format (and set of conventions) for **chunked, compressed, N‑dimensional arrays** that works well on local disks *and* on object stores (S3/GCS/Azure). ExZarr brings that model to Elixir so you can combine:

- Zarr’s partial I/O (read/write just the chunks you need)
- Elixir/OTP concurrency (process many chunks in parallel)
- fault tolerance (supervise ingestion pipelines, retry failures safely)

This post is a practical walk-through. It mirrors the runnable Livebook:
`livebooks/01_core_zarr/01_01_first_zarr_array.livemd`.

---

## What you’ll build

1) Create a Zarr array (in memory and on disk)  
2) Write a slice (rectangular region)  
3) Read a slice back  
4) Stream chunks (sequential + parallel)  
5) Save metadata and reopen the array

---

## The mental model

A Zarr array has:

- `shape` — total dimensions, e.g. `{1000, 1000}`
- `chunks` — chunk dimensions, e.g. `{100, 100}`
- `dtype` — element type, e.g. `:float32`
- `compressor` — e.g. `:zstd`, `:zlib`, `:lz4`, or `:none`
- `storage` — in memory or filesystem (and later: object stores)

When you read a slice, ExZarr loads and decompresses only the chunks that overlap that region.

---

## Quickstart: create a 2D array

```elixir
{:ok, a} =
  ExZarr.Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    compressor: :zstd,
    storage: :memory
  )
```

At this point you have an array handle. Data is created lazily when you write.

---

## Writing a slice

ExZarr writes raw binaries in row-major order. For a `10x10` region of `:int32`,
you need `10 * 10 * 4 = 400` bytes.

In the Livebook we use a tiny helper `ExZarr.Gallery.Pack` to pack numbers to binary.

```elixir
data = ExZarr.Gallery.Pack.pack(Enum.to_list(1..100), :int32)

:ok =
  ExZarr.Array.set_slice(a, data,
    start: {0, 0},
    stop: {10, 10}
  )
```

---

## Reading it back

```elixir
{:ok, bin} =
  ExZarr.Array.get_slice(a,
    start: {0, 0},
    stop: {10, 10}
  )

vals = ExZarr.Gallery.Pack.unpack(bin, :int32)
```

Now `vals` is a flat list (row-major).

---

## Streaming chunks

Chunk streaming is where Zarr starts to feel “cloud native”: you can process an array without loading it all.

```elixir
ExZarr.Array.chunk_stream(a, parallel: 4, ordered: false)
|> Stream.each(fn {chunk_index, bin} ->
  # do something with each chunk
  :ok
end)
|> Stream.run()
```

This is a nice fit for OTP pipelines: bounded concurrency, progress callbacks, and chunk-level isolation.

---

## Saving to disk and reopening

```elixir
path = "/tmp/exzarr_demo/array_2d"
File.rm_rf!(path)
File.mkdir_p!(path)

:ok = ExZarr.Array.save(a, path: path)

{:ok, reopened} = ExZarr.Array.open(path: path)
```

Once saved, you can reopen from other processes (or other languages that implement Zarr v2).

---

## Next steps

If you liked this, the next content in the ExZarr gallery focuses on:

- chunk sizing heuristics (the #1 performance lever)
- compression tradeoffs (CPU vs IO)
- parallel ingestion patterns with backpressure
- AI/GenAI datasets (embeddings, RAG caches, training loaders)
- finance datasets (tick cubes, order books, risk grids)

---

## Links

- ExZarr docs: https://hexdocs.pm/ex_zarr/ExZarr.Array.html
- Zarr v2 spec: https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html
