# Distributed Processing (Experimental)

Multi-node chunk processing is a stretch goal for v1.1.0. The recommended
pattern today is to partition chunk indices across nodes manually:

```elixir
indices = ExZarr.Streaming.chunk_indices(array, include_missing: true)
node_indices = Enum.filter(indices, fn idx -> rem(elem(idx, 0), Node.list() |> length() + 1) == 0 end)

node_indices
|> Enum.map(fn idx ->
  Node.spawn(node, RemoteProcessor, :process_chunk, [array_ref, idx])
end)
```

Investigate Horde and PartitionSupervisor for future releases.
