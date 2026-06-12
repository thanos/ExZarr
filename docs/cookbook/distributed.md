# Distributed Processing (Experimental)

Multi-node chunk processing is a stretch goal for v1.1.0. The recommended
pattern today is to partition chunk indices across nodes manually:

```elixir
nodes = [Node.self() | Node.list()]
node_count = length(nodes)
node_index = 0

node_indices =
  array
  |> ExZarr.Array.stream_chunks(include_missing: true, metadata: true)
  |> Stream.map(& &1.index)
  |> Stream.filter(fn idx -> rem(elem(idx, 0), node_count) == node_index end)
  |> Enum.to_list()

target_node = Enum.at(nodes, node_index)

Enum.each(node_indices, fn idx ->
  Node.spawn(target_node, RemoteProcessor, :process_chunk, [array_ref, idx])
end)
```

Investigate Horde and PartitionSupervisor for future releases.
