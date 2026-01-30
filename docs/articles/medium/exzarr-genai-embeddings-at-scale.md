# Embeddings at scale in Elixir: store vectors in ExZarr and do fast similarity search

This draft pairs with the Livebook:
`livebooks/04_ai_genai/04_01_embeddings_in_zarr.livemd`.

## Why Zarr for embeddings?

Embeddings workloads look like: **many vectors, same dimension**, accessed in batches:

- ingest new documents → append vectors
- query: scan vectors → top‑K cosine similarity
- train: stream mini-batches to the model

Zarr’s chunking lets you optimize for these patterns:
chunk by rows (documents), so each chunk is a batch-sized block.

## What the Livebook demonstrates

- Generate a small corpus (no network calls)
- Produce toy embeddings (hashing trick / bag-of-words)
- Store vectors in a 2D `:float32` ExZarr array
- Run a similarity search by scanning chunks (streaming)
- Discuss how you’d swap in a real embedding model/API

## Practical guidance

- Choose chunks like `{batch_rows, dim}` (e.g. `{512, 1536}` for OpenAI-ish dims)
- Use `chunk_stream/2` with `parallel` to increase throughput on remote stores
- Keep metadata (doc ids, offsets) in a sidecar JSON for now; later you can model a dataset layout convention

## Next articles in the series

- A “batch iterator” for Nx training from Zarr
- RAG cache layout: tokens, logits, features in aligned arrays
- Telemetry tensors for agent runs (time × step × feature)
