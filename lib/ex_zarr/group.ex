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
          attrs: map()
        }

  defstruct [
    :path,
    :storage,
    arrays: %{},
    groups: %{},
    attrs: %{}
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
    array_opts =
      opts
      |> Keyword.put(:storage, group.storage.backend)
      |> Keyword.put(:path, array_path)

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
      |> Keyword.put_new(:path, subgroup_path)

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
