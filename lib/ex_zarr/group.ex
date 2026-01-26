defmodule ExZarr.Group do
  @moduledoc """
  Hierarchical groups for organizing Zarr arrays.

  Groups allow you to organize multiple arrays in a hierarchical structure,
  similar to directories in a filesystem or groups in HDF5. This is useful
  for managing related datasets together.

  ## Group Structure

  A group contains:
  - **Arrays**: Named arrays stored within the group
  - **Subgroups**: Nested groups for hierarchical organization
  - **Attributes**: Metadata key-value pairs
  - **Storage**: Backend storage (shared with child arrays)

  ## Filesystem Layout

  Groups are represented on disk as directories with `.zgroup` files:

      /data/
        .zgroup              # Group metadata
        measurements/
          .zarray            # Array metadata
          0.0, 0.1, ...      # Array chunks
        experiments/
          .zgroup            # Subgroup metadata
          results/
            .zarray
            0.0, 0.1, ...

  ## Examples

      # Create a root group
      {:ok, root} = ExZarr.Group.create("/data",
        storage: :filesystem,
        path: "/tmp/zarr_data"
      )

      # Create arrays in the group
      {:ok, temp} = ExZarr.Group.create_array(root, "temperature",
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float32
      )

      {:ok, pressure} = ExZarr.Group.create_array(root, "pressure",
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float32
      )

      # Create subgroups for organization
      {:ok, exp1} = ExZarr.Group.create_group(root, "experiment_1")
      {:ok, results} = ExZarr.Group.create_array(exp1, "results",
        shape: {500, 500},
        chunks: {50, 50}
      )

      # Add metadata to groups
      root = ExZarr.Group.set_attr(root, "description", "Sensor data collection")
      root = ExZarr.Group.set_attr(root, "version", "1.0")
  """

  alias ExZarr.{Array, Storage}

  @type t :: %__MODULE__{
          path: String.t(),
          storage: Storage.t(),
          arrays: %{String.t() => Array.t()},
          groups: %{String.t() => t()},
          attrs: map(),
          _loaded: MapSet.t(String.t())
        }

  defstruct [
    :path,
    :storage,
    arrays: %{},
    groups: %{},
    attrs: %{},
    _loaded: MapSet.new()
  ]

  @doc """
  Creates a new group.

  ## Options

  - `:storage` - Storage backend (default: `:memory`)
  - `:path` - Path for filesystem storage

  ## Examples

      {:ok, group} = ExZarr.Group.create("/data", storage: :filesystem, path: "/tmp/zarr")
  """
  @spec create(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(group_path, opts \\ []) do
    storage_config = %{
      storage_type: Keyword.get(opts, :storage, :memory),
      path: opts[:path]
    }

    with {:ok, storage} <- Storage.init(storage_config),
         :ok <- write_group_metadata(storage, group_path) do
      group = %__MODULE__{
        path: group_path,
        storage: storage,
        arrays: %{},
        groups: %{},
        attrs: %{}
      }

      {:ok, group}
    end
  end

  @doc """
  Opens an existing group from storage.
  """
  @spec open(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(group_path, opts \\ []) do
    with {:ok, storage} <- Storage.open(opts),
         {:ok, metadata} <- read_group_metadata(storage, group_path) do
      group = %__MODULE__{
        path: group_path,
        storage: storage,
        arrays: %{},
        groups: %{},
        attrs: metadata[:attrs] || %{}
      }

      {:ok, group}
    end
  end

  @doc """
  Creates a new array within this group.

  ## Examples

      {:ok, array} = ExZarr.Group.create_array(group, "measurements",
        shape: {1000},
        chunks: {100},
        dtype: :float64
      )
  """
  @spec create_array(t(), String.t(), keyword()) :: {:ok, Array.t()} | {:error, term()}
  def create_array(group, name, opts) do
    array_path = Path.join(group.path, name)

    # Merge group storage settings with array options
    # For filesystem storage, path needs to be storage.path joined with array_path
    full_path =
      if group.storage.path, do: Path.join(group.storage.path, array_path), else: array_path

    array_opts =
      opts
      |> Keyword.put(:storage, group.storage.backend)
      |> Keyword.put(:path, full_path)

    with {:ok, array} <- Array.create(array_opts) do
      _updated_group = %{group | arrays: Map.put(group.arrays, name, array)}
      {:ok, array}
    end
  end

  @doc """
  Creates a subgroup within this group.

  ## Examples

      {:ok, subgroup} = ExZarr.Group.create_group(group, "experiments")
  """
  @spec create_group(t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create_group(parent_group, name, opts \\ []) do
    subgroup_path = Path.join(parent_group.path, name)

    opts =
      opts
      |> Keyword.put(:storage, parent_group.storage.backend)
      |> Keyword.put_new(:path, parent_group.storage.path)

    with {:ok, subgroup} <- create(subgroup_path, opts) do
      _updated_parent = %{parent_group | groups: Map.put(parent_group.groups, name, subgroup)}
      {:ok, subgroup}
    end
  end

  @doc """
  Gets an array from the group by name.
  """
  @spec get_array(t(), String.t()) :: {:ok, Array.t()} | {:error, :not_found}
  def get_array(group, name) do
    case Map.get(group.arrays, name) do
      nil -> {:error, :not_found}
      array -> {:ok, array}
    end
  end

  @doc """
  Gets a subgroup by name.
  """
  @spec get_group(t(), String.t()) :: {:ok, t()} | {:error, :not_found}
  def get_group(group, name) do
    case Map.get(group.groups, name) do
      nil -> {:error, :not_found}
      subgroup -> {:ok, subgroup}
    end
  end

  @doc """
  Lists all arrays in the group.
  """
  @spec list_arrays(t()) :: [String.t()]
  def list_arrays(group) do
    Map.keys(group.arrays)
  end

  @doc """
  Lists all subgroups.
  """
  @spec list_groups(t()) :: [String.t()]
  def list_groups(group) do
    Map.keys(group.groups)
  end

  @doc """
  Sets an attribute on the group.
  """
  @spec set_attr(t(), String.t(), term()) :: t()
  def set_attr(group, key, value) do
    %{group | attrs: Map.put(group.attrs, key, value)}
  end

  @doc """
  Gets an attribute from the group.
  """
  @spec get_attr(t(), String.t()) :: {:ok, term()} | {:error, :not_found}
  def get_attr(group, key) do
    case Map.get(group.attrs, key) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  ## Access Behavior

  @behaviour Access

  @doc """
  Access nested groups/arrays using path notation.
  Creates intermediate groups on write operations.

  ## Examples

      # Read access
      array = group["temperature"]
      nested = group["experiments/exp1/results"]

      # Write access (auto-creates intermediate groups)
      group = put_in(group["new/path"], array)

      # Update access
      group = update_in(group["data"], fn arr -> modify(arr) end)
  """

  @impl Access
  def fetch(group, key) when is_binary(key) do
    case get_item(group, key) do
      {:ok, item} -> {:ok, item}
      {:error, :not_found} -> :error
    end
  end

  @impl Access
  def get_and_update(group, key, fun) when is_binary(key) do
    current =
      case get_item(group, key) do
        {:ok, item} -> item
        {:error, :not_found} -> nil
      end

    case fun.(current) do
      {get_value, new_value} ->
        updated_group = put_item(group, key, new_value)
        {get_value, updated_group}

      :pop ->
        {current, remove_item(group, key)}
    end
  end

  @impl Access
  def pop(group, key) when is_binary(key) do
    case get_item(group, key) do
      {:ok, item} -> {item, remove_item(group, key)}
      {:error, :not_found} -> {nil, group}
    end
  end

  @doc """
  Gets an item (array or group) at the specified path with lazy loading.

  Paths can be nested using forward slashes: "exp1/run2/data".
  Items are loaded from storage on first access and cached.

  ## Examples

      {:ok, array} = Group.get_item(root, "temperature")
      {:ok, nested} = Group.get_item(root, "experiments/exp1/results")
      {:error, :not_found} = Group.get_item(root, "nonexistent")
  """
  @spec get_item(t(), String.t()) :: {:ok, Array.t() | t()} | {:error, :not_found}
  def get_item(group, path) do
    # Split path into parts
    parts = String.split(path, "/", trim: true)
    get_item_recursive(group, parts, path)
  end

  defp get_item_recursive(group, [], _full_path), do: {:ok, group}

  defp get_item_recursive(group, [name | rest], full_path) do
    # Check in-memory arrays first
    cond do
      Map.has_key?(group.arrays, name) ->
        if rest == [] do
          {:ok, Map.get(group.arrays, name)}
        else
          {:error, :not_found}
        end

      # Check in-memory groups
      Map.has_key?(group.groups, name) ->
        if rest == [] do
          {:ok, Map.get(group.groups, name)}
        else
          get_item_recursive(Map.get(group.groups, name), rest, full_path)
        end

      # If not in memory and not already checked, try loading from storage
      not MapSet.member?(group._loaded, name) ->
        load_item_from_storage(group, name, rest, full_path)

      # Already checked storage, item doesn't exist
      true ->
        {:error, :not_found}
    end
  end

  defp load_item_from_storage(group, name, rest, full_path) do
    child_path = Path.join(group.path, name)

    # Build options for opening
    open_opts = [storage: group.storage.backend]

    open_opts =
      if group.storage.path,
        do: Keyword.put(open_opts, :path, Path.join(group.storage.path, child_path)),
        else: open_opts

    # Try to load as array first
    case ExZarr.open(open_opts) do
      {:ok, array} ->
        # Cache the array
        _updated_group = %{
          group
          | arrays: Map.put(group.arrays, name, array),
            _loaded: MapSet.put(group._loaded, name)
        }

        if rest == [] do
          {:ok, array}
        else
          {:error, :not_found}
        end

      {:error, _} ->
        # Try to load as group
        case open(child_path, open_opts) do
          {:ok, child_group} ->
            # Cache the group
            _updated_group = %{
              group
              | groups: Map.put(group.groups, name, child_group),
                _loaded: MapSet.put(group._loaded, name)
            }

            if rest == [] do
              {:ok, child_group}
            else
              get_item_recursive(child_group, rest, full_path)
            end

          {:error, _} ->
            # Mark as checked
            _updated_group = %{group | _loaded: MapSet.put(group._loaded, name)}
            {:error, :not_found}
        end
    end
  end

  @doc """
  Puts an item (array or group) at the specified path.

  Creates intermediate groups as needed. Returns the updated root group.

  ## Examples

      group = Group.put_item(root, "new/path/array", array)
      group = Group.put_item(root, "experiments/exp1", subgroup)
  """
  @spec put_item(t(), String.t(), Array.t() | t()) :: t()
  def put_item(group, path, item) do
    parts = String.split(path, "/", trim: true)
    put_item_recursive(group, parts, item)
  end

  defp put_item_recursive(group, [name], item) do
    case item do
      %Array{} ->
        %{
          group
          | arrays: Map.put(group.arrays, name, item),
            _loaded: MapSet.put(group._loaded, name)
        }

      %__MODULE__{} ->
        %{
          group
          | groups: Map.put(group.groups, name, item),
            _loaded: MapSet.put(group._loaded, name)
        }
    end
  end

  defp put_item_recursive(group, [name | rest], item) do
    # Get or create intermediate group
    child_group =
      case Map.get(group.groups, name) do
        nil ->
          # Create new intermediate group
          child_path = Path.join(group.path, name)

          %__MODULE__{
            path: child_path,
            storage: group.storage,
            arrays: %{},
            groups: %{},
            attrs: %{},
            _loaded: MapSet.new()
          }

        existing ->
          existing
      end

    # Recursively put in child
    updated_child = put_item_recursive(child_group, rest, item)

    %{
      group
      | groups: Map.put(group.groups, name, updated_child),
        _loaded: MapSet.put(group._loaded, name)
    }
  end

  @doc """
  Removes an item from the group.

  Does not delete from storage, only removes from the in-memory structure.
  The path remains in _loaded to indicate it was checked.

  ## Examples

      group = Group.remove_item(root, "temperature")
      group = Group.remove_item(root, "experiments/exp1")
  """
  @spec remove_item(t(), String.t()) :: t()
  def remove_item(group, path) do
    parts = String.split(path, "/", trim: true)
    remove_item_recursive(group, parts)
  end

  defp remove_item_recursive(group, [name]) do
    %{
      group
      | arrays: Map.delete(group.arrays, name),
        groups: Map.delete(group.groups, name)
    }
  end

  defp remove_item_recursive(group, [name | rest]) do
    case Map.get(group.groups, name) do
      nil ->
        group

      child_group ->
        updated_child = remove_item_recursive(child_group, rest)
        %{group | groups: Map.put(group.groups, name, updated_child)}
    end
  end

  @doc """
  Ensures a group exists at the specified path, creating it if necessary.

  Similar to `mkdir -p`, this creates all intermediate groups along the path.
  If the path exists and is a group, returns it. If it's an array, returns an error.

  ## Examples

      {:ok, group} = Group.require_group(root, "exp1/run2/results")
      {:ok, existing} = Group.require_group(root, "experiments")
      {:error, :path_is_array} = Group.require_group(root, "temperature")
  """
  @spec require_group(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def require_group(parent, path) do
    case get_item(parent, path) do
      {:ok, %__MODULE__{} = group} ->
        {:ok, group}

      {:ok, %Array{}} ->
        {:error, :path_is_array}

      {:error, :not_found} ->
        # Create the group hierarchy
        parts = String.split(path, "/", trim: true)
        create_group_hierarchy(parent, parts)
    end
  end

  defp create_group_hierarchy(parent, parts) do
    case create_groups_recursive(parent, parts) do
      {:ok, _parent, final_group} -> {:ok, final_group}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_groups_recursive(parent, [name]) do
    case create_group(parent, name) do
      {:ok, new_group} ->
        {:ok, parent, new_group}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_groups_recursive(parent, [name | rest]) do
    # Check if group already exists
    case get_item(parent, name) do
      {:ok, %__MODULE__{} = existing_group} ->
        create_groups_recursive(existing_group, rest)

      {:ok, %Array{}} ->
        {:error, :path_is_array}

      {:error, :not_found} ->
        case create_group(parent, name) do
          {:ok, new_group} ->
            create_groups_recursive(new_group, rest)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Generates an ASCII tree visualization of the group hierarchy.

  Uses box-drawing characters to show the structure. Arrays are marked with [A]
  and groups with [G]. Optionally shows array shapes.

  ## Options

  - `:depth` - Maximum depth to display (default: unlimited)
  - `:show_shapes` - Include array shapes in output (default: true)

  ## Examples

      IO.puts(Group.tree(root))
      # Output:
      # /
      # ├── [A] temperature (1000, 1000)
      # ├── [A] pressure (1000, 1000)
      # └── [G] experiments
      #     └── [G] exp1
      #         └── [A] results (500, 500)

      IO.puts(Group.tree(root, depth: 2, show_shapes: false))
  """
  @spec tree(t(), keyword()) :: String.t()
  def tree(group, opts \\ []) do
    show_shapes = Keyword.get(opts, :show_shapes, true)
    max_depth = Keyword.get(opts, :depth, nil)

    lines = [group.path]

    # Get all arrays and groups, sorted by name
    arrays = Enum.sort_by(group.arrays, fn {name, _} -> name end)
    groups = Enum.sort_by(group.groups, fn {name, _} -> name end)
    items = arrays ++ groups

    tree_lines = tree_recursive(items, "", 0, max_depth, show_shapes)
    Enum.join(lines ++ tree_lines, "\n")
  end

  defp tree_recursive([], _prefix, _depth, _max_depth, _show_shapes), do: []

  defp tree_recursive(_items, _prefix, depth, max_depth, _show_shapes)
       when not is_nil(max_depth) and depth >= max_depth do
    []
  end

  defp tree_recursive(items, prefix, depth, max_depth, show_shapes) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{name, item}, index} ->
      is_last = index == length(items) - 1
      connector = if is_last, do: "└── ", else: "├── "
      continuation = if is_last, do: "    ", else: "│   "

      case item do
        %Array{shape: shape} ->
          shape_str = if show_shapes, do: " #{inspect(shape)}", else: ""
          ["#{prefix}#{connector}[A] #{name}#{shape_str}"]

        %__MODULE__{arrays: child_arrays, groups: child_groups} ->
          header = "#{prefix}#{connector}[G] #{name}"

          child_items =
            Enum.sort_by(child_arrays, fn {n, _} -> n end) ++
              Enum.sort_by(child_groups, fn {n, _} -> n end)

          child_prefix = prefix <> continuation
          children = tree_recursive(child_items, child_prefix, depth + 1, max_depth, show_shapes)
          [header | children]
      end
    end)
  end

  @doc """
  Creates multiple groups and/or arrays in parallel.

  Reduces latency for cloud storage by writing metadata concurrently.
  Returns a map of created items keyed by their names.

  ## Examples

      items = [
        {:group, "exp1"},
        {:group, "exp2"},
        {:array, "exp1/results", shape: {100, 100}, chunks: {10, 10}, dtype: :float32}
      ]

      {:ok, created} = Group.batch_create(root, items)
      # created = %{
      #   "exp1" => %Group{...},
      #   "exp2" => %Group{...},
      #   "exp1/results" => %Array{...}
      # }
  """
  @spec batch_create(t(), [{:group | :array, String.t(), keyword()}]) ::
          {:ok, map()} | {:error, term()}
  def batch_create(parent, items) do
    max_concurrency = 10

    results =
      items
      |> Task.async_stream(
        fn
          {:group, name} ->
            {name, create_group(parent, name)}

          {:group, name, _opts} ->
            {name, create_group(parent, name)}

          {:array, name, opts} ->
            {name, create_array(parent, name, opts)}
        end,
        max_concurrency: max_concurrency,
        timeout: 30_000
      )
      |> Enum.to_list()

    # Check for errors
    case Enum.find(results, fn
           {:ok, {_name, {:error, _}}} -> true
           {:exit, _} -> true
           _ -> false
         end) do
      nil ->
        # All successful
        created =
          results
          |> Enum.map(fn {:ok, {name, {:ok, item}}} -> {name, item} end)
          |> Map.new()

        {:ok, created}

      {:ok, {_name, {:error, reason}}} ->
        {:error, reason}

      {:exit, reason} ->
        {:error, reason}
    end
  end

  ## Private Functions

  defp write_group_metadata(storage, group_path) do
    metadata = %{
      zarr_format: 2
    }

    case storage.backend do
      :memory ->
        :ok

      :filesystem ->
        group_file = Path.join([storage.path, group_path, ".zgroup"])
        File.mkdir_p!(Path.dirname(group_file))

        with {:ok, json} <- Jason.encode(metadata, pretty: true) do
          File.write(group_file, json)
        end
    end
  end

  defp read_group_metadata(storage, group_path) do
    case storage.backend do
      # :memory ->
      #   {:ok, %{zarr_format: 2}}

      :filesystem ->
        group_file = Path.join([storage.path, group_path, ".zgroup"])

        with {:ok, json} <- File.read(group_file) do
          Jason.decode(json, keys: :atoms)
        end
    end
  end
end
