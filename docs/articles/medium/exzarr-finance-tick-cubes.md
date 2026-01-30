# Tick data cubes in Elixir with ExZarr: time × symbol × field

This draft pairs with the Livebook:
`livebooks/05_finance/05_01_tick_data_cube.livemd`.

## The cube model

A common “research-friendly” layout is:

- `time` dimension (ticks, seconds, or bars)
- `symbol` dimension (universe)
- `field` dimension (price, size, bid, ask, etc.)

So: `shape = {T, S, F}`

Chunking depends on queries. Typical patterns:

- many symbols, small time window → chunk by `{window, S, F}`
- single symbol, long time window → chunk by `{window, 1, F}` and store per symbol

## What the Livebook demonstrates

- Generate synthetic tick data for a few symbols
- Store it in a 3D Zarr array (`:float64`)
- Compute OHLC and VWAP by streaming chunks
- Use `parallel_chunk_map/3` to scale analytics across chunks

## Why ExZarr fits

- IO is chunked and can be parallelized safely
- CPU work (aggregation) is embarrassingly parallel per chunk
- OTP supervision makes ingestion resilient (retries, backpressure)

## Extensions you can add next

- order book snapshots (level × side × field × time)
- cross-venue cubes for crypto (venue × symbol × time × field)
- “artifact stores” for backtests (features, signals, predictions, metrics)
