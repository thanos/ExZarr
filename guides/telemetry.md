# Telemetry Guide

ExZarr emits telemetry events for monitoring and observability in production environments.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Event Reference](#event-reference)
- [Usage Examples](#usage-examples)
- [Metrics and Monitoring](#metrics-and-monitoring)
- [Integration with Observability Tools](#integration-with-observability-tools)
- [Performance Monitoring](#performance-monitoring)

## Overview

ExZarr uses `:telemetry` for instrumentation, allowing you to:

- **Monitor performance** - Track operation durations and identify bottlenecks
- **Measure throughput** - Count operations and data volumes
- **Track errors** - Monitor failure rates and error types
- **Cache efficiency** - Measure cache hit/miss rates
- **Resource usage** - Monitor memory and I/O patterns

## Installation

Telemetry is included as a dependency in ExZarr v1.0+. To use telemetry events, attach handlers in your application:

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Attach telemetry handlers
    attach_telemetry_handlers()

    children = [
      # Your supervision tree...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp attach_telemetry_handlers do
    events = [
      [:ex_zarr, :array, :create],
      [:ex_zarr, :array, :open],
      [:ex_zarr, :array, :read],
      [:ex_zarr, :array, :write],
      [:ex_zarr, :chunk, :compress],
      [:ex_zarr, :chunk, :decompress],
      [:ex_zarr, :storage, :read],
      [:ex_zarr, :storage, :write],
      [:ex_zarr, :cache, :hit],
      [:ex_zarr, :cache, :miss]
    ]

    :telemetry.attach_many(
      "ex-zarr-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event(event, measurements, metadata, _config) do
    # Log or export metrics
    IO.inspect({event, measurements, metadata})
  end
end
```

## Event Reference

### Array Operations

#### `[:ex_zarr, :array, :create]`

Emitted when an array is created.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:monotonic_time` (integer) - System monotonic time

**Metadata:**
- `:shape` (tuple) - Array shape
- `:chunks` (tuple) - Chunk shape
- `:dtype` (atom) - Data type
- `:compressor` (atom | nil) - Compression codec
- `:storage_type` (atom) - Storage backend type
- `:version` (integer) - Zarr version (2 or 3)

**Example:**
```elixir
%{
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  storage_type: :filesystem,
  version: 2
}
```

#### `[:ex_zarr, :array, :open]`

Emitted when an existing array is opened.

**Measurements:**
- `:duration` (integer) - Time in native units

**Metadata:**
- `:path` (string) - Array path
- `:storage_type` (atom) - Storage backend type
- `:version` (integer) - Detected Zarr version

#### `[:ex_zarr, :array, :read]`

Emitted when reading data from an array.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:bytes` (integer) - Number of bytes read
- `:chunk_count` (integer) - Number of chunks accessed

**Metadata:**
- `:start` (tuple) - Start indices
- `:stop` (tuple) - Stop indices
- `:shape` (tuple) - Array shape
- `:parallel` (boolean) - Whether parallel read was used

**Example:**
```elixir
%{
  start: {0, 0},
  stop: {100, 100},
  shape: {1000, 1000},
  parallel: true
}
```

#### `[:ex_zarr, :array, :write]`

Emitted when writing data to an array.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:bytes` (integer) - Number of bytes written
- `:chunk_count` (integer) - Number of chunks modified

**Metadata:**
- `:start` (tuple) - Start indices
- `:stop` (tuple) - Stop indices
- `:shape` (tuple) - Array shape

### Chunk Operations

#### `[:ex_zarr, :chunk, :compress]`

Emitted when compressing chunk data.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:input_bytes` (integer) - Uncompressed size
- `:output_bytes` (integer) - Compressed size
- `:ratio` (float) - Compression ratio (input/output)

**Metadata:**
- `:codec` (atom) - Compression codec used
- `:level` (integer | nil) - Compression level

**Example:**
```elixir
%{
  codec: :zlib,
  level: 5
}
```

#### `[:ex_zarr, :chunk, :decompress]`

Emitted when decompressing chunk data.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:input_bytes` (integer) - Compressed size
- `:output_bytes` (integer) - Decompressed size

**Metadata:**
- `:codec` (atom) - Compression codec used

### Storage Operations

#### `[:ex_zarr, :storage, :read]`

Emitted when reading from storage backend.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:bytes` (integer) - Number of bytes read

**Metadata:**
- `:backend` (atom) - Storage backend type (:filesystem, :s3, :memory, etc.)
- `:key` (string) - Storage key/path
- `:cache_enabled` (boolean) - Whether caching is enabled

#### `[:ex_zarr, :storage, :write]`

Emitted when writing to storage backend.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:bytes` (integer) - Number of bytes written

**Metadata:**
- `:backend` (atom) - Storage backend type
- `:key` (string) - Storage key/path

#### `[:ex_zarr, :storage, :list]`

Emitted when listing storage keys.

**Measurements:**
- `:duration` (integer) - Time in native units
- `:count` (integer) - Number of keys returned

**Metadata:**
- `:backend` (atom) - Storage backend type
- `:prefix` (string | nil) - List prefix

### Cache Operations

#### `[:ex_zarr, :cache, :hit]`

Emitted when a cache hit occurs.

**Measurements:**
- `:bytes` (integer) - Size of cached data

**Metadata:**
- `:key` (string) - Cache key
- `:chunk_index` (tuple) - Chunk index

#### `[:ex_zarr, :cache, :miss]`

Emitted when a cache miss occurs.

**Metadata:**
- `:key` (string) - Cache key
- `:chunk_index` (tuple) - Chunk index

#### `[:ex_zarr, :cache, :eviction]`

Emitted when a cache entry is evicted.

**Measurements:**
- `:bytes` (integer) - Size of evicted data

**Metadata:**
- `:key` (string) - Cache key
- `:reason` (atom) - Eviction reason (:lru, :size_limit, :manual)

## Usage Examples

### Basic Logging

Simple event logging to console:

```elixir
:telemetry.attach(
  "ex-zarr-logger",
  [:ex_zarr, :array, :read],
  fn event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    IO.puts("""
    Array read completed:
      Duration: #{duration_ms}ms
      Bytes: #{measurements.bytes}
      Chunks: #{measurements.chunk_count}
      Shape: #{inspect(metadata.shape)}
    """)
  end,
  nil
)
```

### Performance Monitoring

Track operation durations and create histograms:

```elixir
:telemetry.attach(
  "ex-zarr-performance",
  [:ex_zarr, :array, :read],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Send to your metrics system
    MyMetrics.histogram("ex_zarr.read.duration", duration_ms,
      tags: ["backend:#{metadata.storage_type}"]
    )

    MyMetrics.histogram("ex_zarr.read.bytes", measurements.bytes)
    MyMetrics.histogram("ex_zarr.read.chunks", measurements.chunk_count)
  end,
  nil
)
```

### Cache Efficiency Monitoring

Track cache hit rates:

```elixir
defmodule MyApp.Telemetry do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{hits: 0, misses: 0}, name: __MODULE__)
  end

  def init(state) do
    :telemetry.attach_many(
      "cache-monitor",
      [
        [:ex_zarr, :cache, :hit],
        [:ex_zarr, :cache, :miss]
      ],
      &handle_cache_event/4,
      nil
    )

    {:ok, state}
  end

  def handle_cache_event([:ex_zarr, :cache, :hit], _measurements, _metadata, _config) do
    GenServer.cast(__MODULE__, :hit)
  end

  def handle_cache_event([:ex_zarr, :cache, :miss], _measurements, _metadata, _config) do
    GenServer.cast(__MODULE__, :miss)
  end

  def handle_cast(:hit, state) do
    {:noreply, Map.update!(state, :hits, &(&1 + 1))}
  end

  def handle_cast(:miss, state) do
    {:noreply, Map.update!(state, :misses, &(&1 + 1))}
  end

  def get_stats do
    GenServer.call(__MODULE__, :stats)
  end

  def handle_call(:stats, _from, state) do
    total = state.hits + state.misses
    hit_rate = if total > 0, do: state.hits / total * 100, else: 0

    {:reply, %{
      hits: state.hits,
      misses: state.misses,
      total: total,
      hit_rate: hit_rate
    }, state}
  end
end
```

### Error Rate Monitoring

Track operation failures:

```elixir
:telemetry.attach(
  "ex-zarr-errors",
  [:ex_zarr, :array, :read, :exception],
  fn _event, _measurements, metadata, _config ->
    # Log error
    Logger.error("ExZarr read failed: #{inspect(metadata.reason)}")

    # Increment error counter
    MyMetrics.increment("ex_zarr.read.errors",
      tags: ["reason:#{metadata.reason}"]
    )
  end,
  nil
)
```

## Metrics and Monitoring

### Key Metrics to Track

#### Performance Metrics

1. **Operation Duration** - Track p50, p95, p99 latencies
   ```elixir
   [:ex_zarr, :array, :read] → measurements.duration
   [:ex_zarr, :array, :write] → measurements.duration
   ```

2. **Throughput** - Operations per second
   ```elixir
   # Count events over time windows
   MyMetrics.increment("ex_zarr.array.reads")
   ```

3. **Data Volume** - Bytes read/written
   ```elixir
   [:ex_zarr, :array, :read] → measurements.bytes
   [:ex_zarr, :storage, :write] → measurements.bytes
   ```

#### Efficiency Metrics

1. **Cache Hit Rate** - Percentage of cache hits
   ```elixir
   hit_rate = cache_hits / (cache_hits + cache_misses) * 100
   ```

2. **Compression Ratio** - Data reduction effectiveness
   ```elixir
   [:ex_zarr, :chunk, :compress] → measurements.ratio
   ```

3. **Parallel Operations** - Track parallel vs sequential reads
   ```elixir
   [:ex_zarr, :array, :read] → metadata.parallel
   ```

#### Resource Metrics

1. **Chunk Count** - Chunks accessed per operation
   ```elixir
   [:ex_zarr, :array, :read] → measurements.chunk_count
   ```

2. **Storage Backend Usage** - Breakdown by backend type
   ```elixir
   [:ex_zarr, :storage, :*] → metadata.backend
   ```

### Sample Metrics Dashboard

Create dashboards with these panels:

**Performance**
- Array read/write latency (p50, p95, p99)
- Compression/decompression duration
- Storage backend latency by type

**Throughput**
- Reads per second
- Writes per second
- Bytes per second (read/write)

**Efficiency**
- Cache hit rate %
- Average compression ratio
- Parallel vs sequential read ratio

**Errors**
- Error rate by operation type
- Error rate by backend type
- Error breakdown by reason

## Integration with Observability Tools

### Prometheus

Using `:telemetry_metrics` and `:telemetry_metrics_prometheus`:

```elixir
# In mix.exs
{:telemetry_metrics, "~> 0.6"},
{:telemetry_metrics_prometheus, "~> 1.1"}

# Setup
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Counters
      counter("ex_zarr.array.reads.count"),
      counter("ex_zarr.array.writes.count"),
      counter("ex_zarr.cache.hits.count"),
      counter("ex_zarr.cache.misses.count"),

      # Distributions (histograms)
      distribution("ex_zarr.array.read.duration",
        unit: {:native, :millisecond},
        buckets: [10, 50, 100, 500, 1000, 5000]
      ),

      distribution("ex_zarr.array.read.bytes",
        buckets: [1024, 10_240, 102_400, 1_024_000, 10_240_000]
      ),

      # Summary
      summary("ex_zarr.chunk.compress.ratio")
    ]
  end
end

# Start Prometheus reporter
{:ok, _} = TelemetryMetricsPrometheus.Core.start_link(
  metrics: MyApp.Telemetry.metrics(),
  port: 9568
)
```

### Datadog

Using `:telemetry_metrics` and Datadog StatsD:

```elixir
# In mix.exs
{:telemetry_metrics, "~> 0.6"},
{:telemetry_metrics_statsd, "~> 0.6"}

# Setup
{:ok, _} = TelemetryMetricsStatsd.start_link(
  metrics: MyApp.Telemetry.metrics(),
  host: "localhost",
  port: 8125,
  global_tags: [env: "production", service: "my_app"]
)
```

### New Relic

Using custom handler:

```elixir
:telemetry.attach_many(
  "newrelic-handler",
  [
    [:ex_zarr, :array, :read],
    [:ex_zarr, :array, :write]
  ],
  fn event, measurements, metadata, _config ->
    NewRelic.add_attributes(
      duration: measurements.duration,
      bytes: measurements.bytes,
      chunks: measurements.chunk_count,
      backend: metadata.storage_type
    )
  end,
  nil
)
```

### OpenTelemetry

Using `:opentelemetry_telemetry`:

```elixir
# In mix.exs
{:opentelemetry, "~> 1.3"},
{:opentelemetry_telemetry, "~> 1.0"}

# Setup
OpentelemetryTelemetry.Handler.attach(
  "ex-zarr-tracer",
  [:ex_zarr, :array, :read],
  %{
    span_name: "ex_zarr.array.read",
    attributes: [:shape, :chunks, :storage_type]
  }
)
```

## Performance Monitoring

### Identifying Bottlenecks

1. **Slow Reads** - Track operations taking >100ms
   ```elixir
   :telemetry.attach(
     "slow-reads",
     [:ex_zarr, :array, :read],
     fn _event, measurements, metadata, _config ->
       duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

       if duration_ms > 100 do
         Logger.warn("Slow read detected: #{duration_ms}ms for #{inspect(metadata.shape)}")
       end
     end,
     nil
   )
   ```

2. **Cache Misses** - Alert on low cache hit rates
   ```elixir
   # Alert if hit rate drops below 80%
   if cache_hit_rate < 80 do
     Logger.warn("Low cache hit rate: #{cache_hit_rate}%")
   end
   ```

3. **Large Operations** - Monitor memory-intensive operations
   ```elixir
   if measurements.bytes > 100_000_000 do  # >100MB
     Logger.info("Large operation: #{measurements.bytes} bytes")
   end
   ```

### Performance Tuning

Use telemetry data to tune ExZarr:

1. **Chunk Size** - Monitor chunk count vs duration
   - High chunk count → Consider larger chunks
   - Low parallel usage → Enable parallel reads

2. **Cache Settings** - Optimize based on hit rates
   - Low hit rate → Increase cache size
   - High eviction rate → Adjust eviction policy

3. **Compression** - Balance speed vs ratio
   - High compression duration → Use faster codec
   - Low compression ratio → Consider different codec

## Best Practices

1. **Aggregate Metrics** - Use time windows (1min, 5min, 1hour)
2. **Tag Strategically** - Add useful tags (backend, codec, version)
3. **Monitor Errors** - Track all exception events
4. **Set Alerts** - Configure alerts for anomalies
5. **Dashboard Everything** - Visualize all key metrics
6. **Correlate Events** - Connect related telemetry events
7. **Performance Budget** - Set and monitor SLOs

## Troubleshooting

### No Events Firing

```elixir
# Check telemetry handlers
:telemetry.list_handlers([])

# Verify handler is attached
:telemetry.list_handlers([:ex_zarr, :array, :read])
```

### High Event Volume

```elixir
# Sample events (only handle 10%)
:telemetry.attach(
  "sampled-handler",
  [:ex_zarr, :array, :read],
  fn event, measurements, metadata, _config ->
    if :rand.uniform(10) == 1 do
      handle_event(event, measurements, metadata)
    end
  end,
  nil
)
```

### Memory Concerns

Telemetry events are lightweight, but if concerned about memory:

1. Detach unused handlers
2. Use sampling for high-frequency events
3. Avoid storing large metadata

```elixir
# Detach handler
:telemetry.detach("handler-id")

# Detach all handlers for event
:telemetry.detach_many([:ex_zarr, :array, :read])
```

## See Also

- [Telemetry Library Documentation](https://hexdocs.pm/telemetry)
- [Telemetry Metrics](https://hexdocs.pm/telemetry_metrics)
- [Performance Guide](performance.md)
- [Error Handling Guide](error_handling.md)
