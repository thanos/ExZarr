defmodule ExZarr.Version do
  @moduledoc """
  Version detection and routing for Zarr v2 and v3 formats.

  This module provides utilities for detecting which Zarr specification version
  is being used and managing version-specific behavior throughout the library.

  ## Supported Versions

  - **Zarr v2**: Original specification with `.zarray`/`.zgroup` metadata files
  - **Zarr v3**: New specification with unified `zarr.json` metadata format

  ## Version Detection

  Versions are detected from the `zarr_format` field in metadata:

      iex> ExZarr.Version.detect_version(%{"zarr_format" => 2})
      {:ok, 2}

      iex> ExZarr.Version.detect_version(%{"zarr_format" => 3})
      {:ok, 3}

  ## Default Version

  The default version for new arrays can be configured:

      # config/config.exs
      config :ex_zarr, default_zarr_version: 3

  If not configured, v3 is used by default for new arrays.
  """

  @type version :: 2 | 3
  @type version_error :: :missing_zarr_format | {:unsupported_version, integer()}

  @doc """
  Detects the Zarr format version from metadata JSON.

  ## Parameters

    * `metadata_json` - Decoded metadata map containing `zarr_format` field

  ## Returns

    * `{:ok, version}` - Version 2 or 3
    * `{:error, :missing_zarr_format}` - No `zarr_format` field found
    * `{:error, {:unsupported_version, v}}` - Unsupported version number

  ## Examples

      iex> ExZarr.Version.detect_version(%{"zarr_format" => 2})
      {:ok, 2}

      iex> ExZarr.Version.detect_version(%{"zarr_format" => 3})
      {:ok, 3}

      iex> ExZarr.Version.detect_version(%{"zarr_format" => 4})
      {:error, {:unsupported_version, 4}}

      iex> ExZarr.Version.detect_version(%{})
      {:error, :missing_zarr_format}
  """
  @spec detect_version(map()) :: {:ok, version()} | {:error, version_error()}
  def detect_version(metadata_json) when is_map(metadata_json) do
    # Handle both string keys (from JSON) and atom keys (from internal maps)
    zarr_format = Map.get(metadata_json, "zarr_format") || Map.get(metadata_json, :zarr_format)

    case zarr_format do
      2 ->
        {:ok, 2}

      3 ->
        {:ok, 3}

      nil ->
        {:error, :missing_zarr_format}

      unsupported_version when is_integer(unsupported_version) ->
        {:error, {:unsupported_version, unsupported_version}}

      other ->
        {:error, {:invalid_version_type, other}}
    end
  end

  @doc """
  Returns the default Zarr version for new arrays.

  The default can be configured via application config:

      config :ex_zarr, default_zarr_version: 2  # or 3

  If not configured, defaults to version 3.

  ## Returns

    * `2` or `3` - The default version number

  ## Examples

      iex> ExZarr.Version.default_version()
      3
  """
  @spec default_version() :: version()
  def default_version do
    Application.get_env(:ex_zarr, :default_zarr_version, 3)
  end

  @doc """
  Returns the list of supported Zarr specification versions.

  ## Returns

    * List of supported version numbers

  ## Examples

      iex> ExZarr.Version.supported_versions()
      [2, 3]
  """
  @spec supported_versions() :: [version(), ...]
  def supported_versions, do: [2, 3]

  @doc """
  Checks if a version number is supported.

  ## Parameters

    * `version` - Version number to check

  ## Returns

    * `true` if version is supported
    * `false` otherwise

  ## Examples

      iex> ExZarr.Version.supported?(2)
      true

      iex> ExZarr.Version.supported?(3)
      true

      iex> ExZarr.Version.supported?(4)
      false
  """
  @spec supported?(integer()) :: boolean()
  def supported?(version) when is_integer(version) do
    version in supported_versions()
  end

  @doc """
  Returns the metadata filename for a given version.

  - v2 uses `.zarray` for arrays and `.zgroup` for groups
  - v3 uses unified `zarr.json` for both

  ## Parameters

    * `version` - Zarr format version (2 or 3)
    * `node_type` - Type of node (`:array` or `:group`, default `:array`)

  ## Returns

    * Metadata filename string

  ## Examples

      iex> ExZarr.Version.metadata_filename(2)
      ".zarray"

      iex> ExZarr.Version.metadata_filename(2, :group)
      ".zgroup"

      iex> ExZarr.Version.metadata_filename(3)
      "zarr.json"

      iex> ExZarr.Version.metadata_filename(3, :group)
      "zarr.json"
  """
  @spec metadata_filename(version(), :array | :group) :: String.t()
  def metadata_filename(version, node_type \\ :array)
  def metadata_filename(2, :array), do: ".zarray"
  def metadata_filename(2, :group), do: ".zgroup"
  def metadata_filename(3, _node_type), do: "zarr.json"
end
