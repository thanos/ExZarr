defmodule ExZarr.ConsolidatedMetadata do
  @moduledoc """
  Consolidated metadata for Zarr groups and arrays.

  Consolidated metadata stores all array and group metadata in a single
  `.zmetadata` file at the group root. This dramatically reduces the number
  of storage API calls needed to open a group, especially beneficial for
  cloud storage (S3, GCS) where API calls have significant latency and cost.

  ## Benefits

  - **Reduced API calls**: Single read instead of N reads for N arrays
  - **Faster group opening**: ~90-99% reduction in cloud storage requests
  - **Cost savings**: Fewer S3/GCS API calls reduce costs
  - **Atomic metadata**: Consistent snapshot of all metadata

  ## Format

  The `.zmetadata` file contains a JSON object with:

  ```json
  {
    "zarr_consolidated_format": 1,
    "metadata": {
      ".zattrs": {...},
      ".zgroup": {...},
      "array1/.zarray": {...},
      "array1/.zattrs": {...},
      "array2/.zarray": {...},
      "array2/.zattrs": {...}
    }
  }
  ```

  ## Usage

      # Consolidate metadata for a group
      {:ok, _count} = ExZarr.ConsolidatedMetadata.consolidate(
        path: "/path/to/group",
        storage: :filesystem
      )

      # Check if consolidated metadata exists
      true = ExZarr.ConsolidatedMetadata.exists?(
        path: "/path/to/group",
        storage: :filesystem
      )

      # Read consolidated metadata
      {:ok, metadata_map} = ExZarr.ConsolidatedMetadata.read(
        path: "/path/to/group",
        storage: :filesystem
      )

  ## Compatibility

  - Compatible with zarr-python consolidated metadata
  - Works with both Zarr v2 and v3 formats
  - Optional feature - arrays work fine without it
  """

  @consolidated_format_version 1
  @consolidated_filename ".zmetadata"

  @type metadata_map :: %{String.t() => map()}
  @type consolidate_opts :: [path: String.t(), storage: atom(), recursive: boolean()]

  @doc """
  Consolidate metadata for a Zarr group.

  Reads all array and group metadata files within a group and writes them
  to a single `.zmetadata` file.

  ## Options

    * `:path` - Path to the group directory (required)
    * `:storage` - Storage backend atom (default: `:filesystem`)
    * `:recursive` - Include nested groups (default: `true`)

  ## Returns

    * `{:ok, count}` - Number of metadata entries consolidated
    * `{:error, reason}` - Consolidation failed

  ## Examples

      # Consolidate a group
      {:ok, 5} = ExZarr.ConsolidatedMetadata.consolidate(
        path: "/data/my_group",
        storage: :filesystem
      )

      # Non-recursive consolidation
      {:ok, 2} = ExZarr.ConsolidatedMetadata.consolidate(
        path: "/data/my_group",
        storage: :filesystem,
        recursive: false
      )
  """
  @spec consolidate(consolidate_opts()) :: {:ok, non_neg_integer()} | {:error, term()}
  def consolidate(opts) do
    path = Keyword.fetch!(opts, :path)
    _storage = Keyword.get(opts, :storage, :filesystem)
    recursive = Keyword.get(opts, :recursive, true)

    with {:ok, entries} <- collect_metadata_entries(path, "", recursive) do
      consolidated = %{
        zarr_consolidated_format: @consolidated_format_version,
        metadata: entries
      }

      json = Jason.encode!(consolidated, pretty: true)
      consolidated_path = Path.join(path, @consolidated_filename)

      case write_consolidated_file(consolidated_path, json) do
        :ok -> {:ok, map_size(entries)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Read consolidated metadata from a group.

  Returns a map of metadata entries keyed by their relative paths.

  ## Options

    * `:path` - Path to the group directory (required)
    * `:storage` - Storage backend atom (default: `:filesystem`)

  ## Returns

    * `{:ok, metadata_map}` - Map of relative_path => metadata
    * `{:error, :not_found}` - No consolidated metadata exists
    * `{:error, reason}` - Read failed

  ## Examples

      {:ok, metadata} = ExZarr.ConsolidatedMetadata.read(
        path: "/data/my_group",
        storage: :filesystem
      )

      # Access specific array metadata
      array_meta = metadata["array1/.zarray"]
  """
  @spec read(keyword()) :: {:ok, metadata_map()} | {:error, term()}
  def read(opts) do
    path = Keyword.fetch!(opts, :path)
    _storage = Keyword.get(opts, :storage, :filesystem)

    with {:ok, json} <- read_consolidated_file(path) do
      case Jason.decode(json) do
        {:ok, %{"metadata" => metadata}} -> {:ok, metadata}
        {:ok, _} -> {:error, :invalid_format}
        {:error, reason} -> {:error, {:json_decode_error, reason}}
      end
    end
  end

  @doc """
  Check if consolidated metadata exists for a group.

  ## Options

    * `:path` - Path to the group directory (required)
    * `:storage` - Storage backend atom (default: `:filesystem`)

  ## Returns

    * `true` - Consolidated metadata exists
    * `false` - No consolidated metadata

  ## Examples

      if ExZarr.ConsolidatedMetadata.exists?(path: "/data/my_group") do
        # Use consolidated metadata for faster access
      end
  """
  @spec exists?(keyword()) :: boolean()
  def exists?(opts) do
    path = Keyword.fetch!(opts, :path)
    _storage = Keyword.get(opts, :storage, :filesystem)

    consolidated_path = Path.join(path, @consolidated_filename)
    file_exists?(consolidated_path)
  end

  @doc """
  Remove consolidated metadata from a group.

  Deletes the `.zmetadata` file. Individual metadata files are not affected.

  ## Options

    * `:path` - Path to the group directory (required)
    * `:storage` - Storage backend atom (default: `:filesystem`)

  ## Returns

    * `:ok` - Consolidated metadata removed or didn't exist
    * `{:error, reason}` - Removal failed
  """
  @spec remove(keyword()) :: :ok | {:error, atom()}
  def remove(opts) do
    path = Keyword.fetch!(opts, :path)
    _storage = Keyword.get(opts, :storage, :filesystem)

    consolidated_path = Path.join(path, @consolidated_filename)
    delete_file(consolidated_path)
  end

  ## Private Functions

  defp collect_metadata_entries(base_path, relative_prefix, recursive) do
    entries = %{}

    # Read group metadata if exists
    entries =
      case read_metadata_file(base_path, ".zgroup") do
        {:ok, zgroup_json} ->
          Map.put(entries, Path.join(relative_prefix, ".zgroup"), Jason.decode!(zgroup_json))

        _ ->
          entries
      end

    # Read group attributes if exists
    entries =
      case read_metadata_file(base_path, ".zattrs") do
        {:ok, zattrs_json} ->
          Map.put(entries, Path.join(relative_prefix, ".zattrs"), Jason.decode!(zattrs_json))

        _ ->
          entries
      end

    # Find all arrays and nested groups
    case list_directory(base_path) do
      {:ok, items} ->
        entries =
          Enum.reduce(items, entries, fn item, acc ->
            item_path = Path.join(base_path, item)
            item_rel = Path.join(relative_prefix, item)

            cond do
              # Check if it's an array (has .zarray or zarr.json)
              array?(item_path) ->
                collect_array_metadata(item_path, item_rel, acc)

              # Check if it's a group (has .zgroup or zarr.json with node_type: group)
              recursive && group?(item_path) ->
                case collect_metadata_entries(item_path, item_rel, recursive) do
                  {:ok, nested_entries} -> Map.merge(acc, nested_entries)
                  _ -> acc
                end

              true ->
                acc
            end
          end)

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_array_metadata(array_path, relative_path, entries) do
    # Try v3 first (zarr.json)
    case read_metadata_file(array_path, "zarr.json") do
      {:ok, json} ->
        entries
        |> Map.put(Path.join(relative_path, "zarr.json"), Jason.decode!(json))

      {:error, _} ->
        # Fall back to v2 (.zarray)
        entries =
          case read_metadata_file(array_path, ".zarray") do
            {:ok, zarray_json} ->
              Map.put(entries, Path.join(relative_path, ".zarray"), Jason.decode!(zarray_json))

            _ ->
              entries
          end

        # Also get attributes if present
        case read_metadata_file(array_path, ".zattrs") do
          {:ok, zattrs_json} ->
            Map.put(entries, Path.join(relative_path, ".zattrs"), Jason.decode!(zattrs_json))

          _ ->
            entries
        end
    end
  end

  defp array?(path) do
    file_exists?(Path.join(path, ".zarray")) ||
      file_exists?(Path.join(path, "zarr.json"))
  end

  defp group?(path) do
    # A directory is a group if it has a .zgroup file OR if it's a directory
    # that contains arrays/groups (but is not itself an array)
    has_zgroup = file_exists?(Path.join(path, ".zgroup"))
    is_directory = File.dir?(path)
    is_not_array = !array?(path)

    has_zgroup || (is_directory && is_not_array)
  end

  defp read_metadata_file(base_path, filename) do
    file_path = Path.join(base_path, filename)

    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp write_consolidated_file(path, json) do
    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_consolidated_file(base_path) do
    consolidated_path = Path.join(base_path, @consolidated_filename)

    case File.read(consolidated_path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp file_exists?(path) do
    File.exists?(path)
  end

  defp list_directory(path) do
    case File.ls(path) do
      {:ok, items} ->
        # Filter out metadata files and lock files
        filtered =
          Enum.reject(items, fn item ->
            item in [@consolidated_filename, ".zarray", ".zattrs", ".zgroup", "zarr.json"] ||
              String.ends_with?(item, ".lock")
          end)

        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
