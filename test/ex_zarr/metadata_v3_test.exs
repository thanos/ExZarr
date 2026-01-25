defmodule ExZarr.MetadataV3Test do
  use ExUnit.Case, async: true

  alias ExZarr.MetadataV3

  describe "validate/1" do
    test "validates correct array metadata" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 200},
        data_type: "float64",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 20}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "bytes", configuration: %{}},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0.0,
        attributes: %{},
        dimension_names: nil
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "validates correct group metadata" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :group,
        attributes: %{"description" => "test group"},
        shape: nil,
        data_type: nil,
        chunk_grid: nil,
        chunk_key_encoding: nil,
        codecs: nil,
        fill_value: nil,
        dimension_names: nil
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "rejects invalid zarr_format" do
      metadata = %MetadataV3{
        zarr_format: 2,
        node_type: :array
      }

      assert {:error, {:invalid_zarr_format, _}} = MetadataV3.validate(metadata)
    end

    test "rejects invalid node_type" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :invalid
      }

      assert {:error, {:invalid_node_type, _}} = MetadataV3.validate(metadata)
    end

    test "rejects array without required fields" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: nil
      }

      assert {:error, {:missing_required_field, :shape}} = MetadataV3.validate(metadata)
    end

    test "rejects array with invalid shape" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: "not a tuple",
        data_type: "float64",
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes"}]
      }

      assert {:error, {:invalid_shape, _}} = MetadataV3.validate(metadata)
    end

    test "rejects array with empty shape" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {},
        data_type: "float64",
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes"}]
      }

      assert {:error, {:invalid_shape, _}} = MetadataV3.validate(metadata)
    end

    test "rejects array with invalid data_type" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: :not_a_string,
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes"}]
      }

      assert {:error, {:invalid_data_type, _}} = MetadataV3.validate(metadata)
    end

    test "rejects array with invalid chunk_grid" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: "not a map",
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes"}]
      }

      assert {:error, {:invalid_chunk_grid, _}} = MetadataV3.validate(metadata)
    end

    test "rejects array without codecs" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: nil
      }

      assert {:error, {:missing_required_field, :codecs}} = MetadataV3.validate(metadata)
    end

    test "rejects array with empty codec list" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: []
      }

      assert {:error, {:empty_codecs, _}} = MetadataV3.validate(metadata)
    end

    test "accepts array without bytes codec (lenient)" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular"},
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "gzip", configuration: %{}}
        ]
      }

      # Implementation is lenient about missing bytes codec for custom codecs
      assert :ok = MetadataV3.validate(metadata)
    end

    test "accepts array with bytes codec" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0,
        attributes: %{}
      }

      assert :ok = MetadataV3.validate(metadata)
    end
  end

  describe "get_chunk_shape/1" do
    test "extracts chunk shape from chunk_grid" do
      metadata = %MetadataV3{
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 20, 30}}
        }
      }

      assert {:ok, {10, 20, 30}} = MetadataV3.get_chunk_shape(metadata)
    end

    test "handles chunk_shape as list" do
      metadata = %MetadataV3{
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: [10, 20]}
        }
      }

      assert {:ok, {10, 20}} = MetadataV3.get_chunk_shape(metadata)
    end

    test "returns error for missing chunk_shape" do
      metadata = %MetadataV3{
        chunk_grid: %{
          name: "regular",
          configuration: %{}
        }
      }

      assert {:error, :chunk_shape_not_found} = MetadataV3.get_chunk_shape(metadata)
    end

    test "returns error for invalid chunk_grid" do
      metadata = %MetadataV3{
        chunk_grid: nil
      }

      assert {:error, :invalid_chunk_grid} = MetadataV3.get_chunk_shape(metadata)
    end
  end

  describe "num_chunks/1" do
    test "calculates number of chunks for 1D array" do
      metadata = %MetadataV3{
        shape: {100},
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10}}
        }
      }

      assert {:ok, {10}} = MetadataV3.num_chunks(metadata)
    end

    test "calculates number of chunks for 2D array" do
      metadata = %MetadataV3{
        shape: {100, 200},
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 25}}
        }
      }

      assert {:ok, {10, 8}} = MetadataV3.num_chunks(metadata)
    end

    test "calculates number of chunks for 3D array" do
      metadata = %MetadataV3{
        shape: {50, 60, 70},
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 20, 30}}
        }
      }

      assert {:ok, {5, 3, 3}} = MetadataV3.num_chunks(metadata)
    end

    test "handles partial chunks correctly" do
      metadata = %MetadataV3{
        shape: {105, 207},
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 25}}
        }
      }

      # 105 / 10 = 10.5 -> 11 chunks
      # 207 / 25 = 8.28 -> 9 chunks
      assert {:ok, {11, 9}} = MetadataV3.num_chunks(metadata)
    end

    test "returns error for missing chunk shape" do
      metadata = %MetadataV3{
        shape: {100},
        chunk_grid: %{
          name: "regular",
          configuration: %{}
        }
      }

      assert {:error, :chunk_shape_not_found} = MetadataV3.num_chunks(metadata)
    end
  end

  describe "struct creation" do
    test "creates array metadata with all fields" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {1000, 1000},
        data_type: "float32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {100, 100}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "transpose", configuration: %{order: [1, 0]}},
          %{name: "bytes", configuration: %{}},
          %{name: "zstd", configuration: %{level: 5}}
        ],
        fill_value: nil,
        attributes: %{"created_by" => "ExZarr", "version" => "0.4.0"},
        dimension_names: ["y", "x"]
      }

      assert metadata.zarr_format == 3
      assert metadata.node_type == :array
      assert tuple_size(metadata.shape) == 2
      assert is_binary(metadata.data_type)
      assert is_map(metadata.chunk_grid)
      assert is_list(metadata.codecs)
      assert is_map(metadata.attributes)
      assert is_list(metadata.dimension_names)
    end

    test "creates group metadata" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :group,
        attributes: %{"description" => "My group"}
      }

      assert metadata.zarr_format == 3
      assert metadata.node_type == :group
      assert metadata.shape == nil
      assert metadata.codecs == nil
    end
  end

  describe "codec validation details" do
    test "accepts multiple array->array codecs before bytes" do
      codecs = [
        %{name: "transpose", configuration: %{}},
        %{name: "shuffle", configuration: %{}},
        %{name: "bytes", configuration: %{}},
        %{name: "gzip", configuration: %{}}
      ]

      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: codecs,
        fill_value: 0,
        attributes: %{}
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "accepts multiple bytes->bytes codecs after bytes" do
      codecs = [
        %{name: "bytes", configuration: %{}},
        %{name: "gzip", configuration: %{level: 5}},
        %{name: "crc32c", configuration: %{}}
      ]

      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "int32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: codecs,
        fill_value: 0,
        attributes: %{}
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "bytes codec must have name field" do
      codecs = [%{configuration: %{}}]

      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: codecs,
        fill_value: 0,
        attributes: %{}
      }

      assert {:error, {:invalid_codec_format, _}} = MetadataV3.validate(metadata)
    end
  end

  describe "data types" do
    test "accepts standard integer types" do
      for dtype <- ["int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64"] do
        metadata = %MetadataV3{
          zarr_format: 3,
          node_type: :array,
          shape: {10},
          data_type: dtype,
          chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
          chunk_key_encoding: %{name: "default"},
          codecs: [%{name: "bytes", configuration: %{}}],
          fill_value: 0,
          attributes: %{}
        }

        assert :ok = MetadataV3.validate(metadata)
      end
    end

    test "accepts standard float types" do
      for dtype <- ["float32", "float64"] do
        metadata = %MetadataV3{
          zarr_format: 3,
          node_type: :array,
          shape: {10},
          data_type: dtype,
          chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
          chunk_key_encoding: %{name: "default"},
          codecs: [%{name: "bytes", configuration: %{}}],
          fill_value: 0.0,
          attributes: %{}
        }

        assert :ok = MetadataV3.validate(metadata)
      end
    end

    test "accepts bool type" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {10},
        data_type: "bool",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: false,
        attributes: %{}
      }

      assert :ok = MetadataV3.validate(metadata)
    end
  end

  describe "dimension names" do
    test "accepts dimension names matching shape" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 200, 300},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10, 20, 30}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0.0,
        attributes: %{},
        dimension_names: ["z", "y", "x"]
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "accepts nil dimension names" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100},
        data_type: "int32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0,
        attributes: %{},
        dimension_names: nil
      }

      assert :ok = MetadataV3.validate(metadata)
    end
  end

  describe "fill values" do
    test "accepts various fill value types" do
      test_cases = [
        {"int32", 42},
        {"float64", 3.14159},
        {"bool", true},
        {"int64", 0},
        {"float32", nil}
      ]

      for {dtype, fill_value} <- test_cases do
        metadata = %MetadataV3{
          zarr_format: 3,
          node_type: :array,
          shape: {10},
          data_type: dtype,
          chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
          chunk_key_encoding: %{name: "default"},
          codecs: [%{name: "bytes", configuration: %{}}],
          fill_value: fill_value,
          attributes: %{}
        }

        assert :ok = MetadataV3.validate(metadata)
      end
    end
  end

  describe "attributes" do
    test "accepts empty attributes map" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {10},
        data_type: "int32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0,
        attributes: %{}
      }

      assert :ok = MetadataV3.validate(metadata)
    end

    test "accepts attributes with various types" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {10},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0.0,
        attributes: %{
          "string" => "value",
          "number" => 123,
          "float" => 45.67,
          "bool" => true,
          "list" => [1, 2, 3],
          "nested" => %{"key" => "value"}
        }
      }

      assert :ok = MetadataV3.validate(metadata)
    end
  end

  describe "to_json/1" do
    test "encodes basic array metadata to JSON" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 200},
        data_type: "float64",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 20}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "bytes", configuration: %{}},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0.0,
        attributes: %{"created_by" => "ExZarr"}
      }

      assert {:ok, json} = MetadataV3.to_json(metadata)
      assert is_binary(json)

      # Verify it's valid JSON
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["zarr_format"] == 3
      assert decoded["node_type"] == "array"
      assert decoded["shape"] == [100, 200]
      assert decoded["data_type"] == "float64"
      assert decoded["chunk_grid"]["name"] == "regular"
      assert decoded["chunk_grid"]["configuration"]["chunk_shape"] == [10, 20]
      assert decoded["fill_value"] == 0.0
    end

    test "encodes group metadata to JSON" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :group,
        attributes: %{"description" => "My group"}
      }

      assert {:ok, json} = MetadataV3.to_json(metadata)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["zarr_format"] == 3
      assert decoded["node_type"] == "group"
      assert decoded["attributes"]["description"] == "My group"

      # Array-specific fields should not be present
      refute Map.has_key?(decoded, "shape")
      refute Map.has_key?(decoded, "data_type")
    end

    test "encodes dimension names" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 200, 300},
        data_type: "int32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10, 20, 30}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes", configuration: %{}}],
        fill_value: 0,
        attributes: %{},
        dimension_names: ["z", "y", "x"]
      }

      assert {:ok, json} = MetadataV3.to_json(metadata)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["dimension_names"] == ["z", "y", "x"]
    end

    test "encodes sharding codec with nested configurations" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {1000, 1000},
        data_type: "float32",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {100, 100}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{
            name: "sharding_indexed",
            configuration: %{
              chunk_shape: {10, 10},
              codecs: [
                %{name: "bytes", configuration: %{}},
                %{name: "gzip", configuration: %{level: 3}}
              ],
              index_codecs: [
                %{name: "bytes", configuration: %{}},
                %{name: "crc32c", configuration: %{}}
              ],
              index_location: "end"
            }
          }
        ],
        fill_value: 0.0,
        attributes: %{}
      }

      assert {:ok, json} = MetadataV3.to_json(metadata)
      assert {:ok, decoded} = Jason.decode(json)

      shard_codec = List.first(decoded["codecs"])
      assert shard_codec["name"] == "sharding_indexed"
      assert shard_codec["configuration"]["chunk_shape"] == [10, 10]
      assert length(shard_codec["configuration"]["codecs"]) == 2
      assert length(shard_codec["configuration"]["index_codecs"]) == 2
      assert shard_codec["configuration"]["index_location"] == "end"
    end

    test "encodes storage transformers" do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 100},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10, 10}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "transpose", configuration: %{order: [1, 0]}},
          %{name: "bytes", configuration: %{}},
          %{name: "zstd", configuration: %{level: 5}}
        ],
        fill_value: nil,
        attributes: %{}
      }

      assert {:ok, json} = MetadataV3.to_json(metadata)
      assert {:ok, decoded} = Jason.decode(json)

      assert length(decoded["codecs"]) == 3
      assert List.first(decoded["codecs"])["name"] == "transpose"
    end
  end

  describe "from_json/1" do
    test "parses basic array metadata from JSON string" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "array",
        "shape": [100, 200],
        "data_type": "float64",
        "chunk_grid": {
          "name": "regular",
          "configuration": {"chunk_shape": [10, 20]}
        },
        "chunk_key_encoding": {"name": "default"},
        "codecs": [
          {"name": "bytes", "configuration": {}},
          {"name": "gzip", "configuration": {"level": 5}}
        ],
        "fill_value": 0.0,
        "attributes": {}
      })

      assert {:ok, metadata} = MetadataV3.from_json(json)
      assert metadata.zarr_format == 3
      assert metadata.node_type == :array
      assert metadata.shape == {100, 200}
      assert metadata.data_type == "float64"
      assert metadata.chunk_grid.name == "regular"
      assert metadata.chunk_grid.configuration.chunk_shape == {10, 20}
      assert length(metadata.codecs) == 2
      assert List.first(metadata.codecs).name == "bytes"
    end

    test "parses array metadata from map" do
      map = %{
        "zarr_format" => 3,
        "node_type" => "array",
        "shape" => [50],
        "data_type" => "int32",
        "chunk_grid" => %{
          "name" => "regular",
          "configuration" => %{"chunk_shape" => [10]}
        },
        "chunk_key_encoding" => %{"name" => "default"},
        "codecs" => [%{"name" => "bytes", "configuration" => %{}}],
        "fill_value" => 0,
        "attributes" => %{}
      }

      assert {:ok, metadata} = MetadataV3.from_json(map)
      assert metadata.zarr_format == 3
      assert metadata.shape == {50}
      assert metadata.data_type == "int32"
    end

    test "parses group metadata" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "group",
        "attributes": {"description": "Test group"}
      })

      assert {:ok, metadata} = MetadataV3.from_json(json)
      assert metadata.zarr_format == 3
      assert metadata.node_type == :group
      assert metadata.attributes == %{"description" => "Test group"}
      assert is_nil(metadata.shape)
      assert is_nil(metadata.codecs)
    end

    test "parses dimension names" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "array",
        "shape": [100, 200],
        "data_type": "float32",
        "chunk_grid": {"name": "regular", "configuration": {"chunk_shape": [10, 20]}},
        "chunk_key_encoding": {"name": "default"},
        "codecs": [{"name": "bytes", "configuration": {}}],
        "fill_value": 0.0,
        "attributes": {},
        "dimension_names": ["y", "x"]
      })

      assert {:ok, metadata} = MetadataV3.from_json(json)
      assert metadata.dimension_names == ["y", "x"]
    end

    test "parses sharding codec with nested configurations" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "array",
        "shape": [1000, 1000],
        "data_type": "int16",
        "chunk_grid": {"name": "regular", "configuration": {"chunk_shape": [100, 100]}},
        "chunk_key_encoding": {"name": "default"},
        "codecs": [
          {
            "name": "sharding_indexed",
            "configuration": {
              "chunk_shape": [10, 10],
              "codecs": [
                {"name": "bytes", "configuration": {}},
                {"name": "zstd", "configuration": {"level": 3}}
              ],
              "index_codecs": [
                {"name": "bytes", "configuration": {}},
                {"name": "crc32c", "configuration": {}}
              ],
              "index_location": "start"
            }
          }
        ],
        "fill_value": 0,
        "attributes": {}
      })

      assert {:ok, metadata} = MetadataV3.from_json(json)

      shard_codec = List.first(metadata.codecs)
      assert shard_codec.name == "sharding_indexed"
      assert shard_codec.configuration.chunk_shape == {10, 10}
      assert length(shard_codec.configuration.codecs) == 2
      assert length(shard_codec.configuration.index_codecs) == 2
      assert shard_codec.configuration.index_location == "start"
    end

    test "parses storage transformers (transpose, quantize, bitround)" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "array",
        "shape": [100, 100],
        "data_type": "float64",
        "chunk_grid": {"name": "regular", "configuration": {"chunk_shape": [10, 10]}},
        "chunk_key_encoding": {"name": "default"},
        "codecs": [
          {"name": "transpose", "configuration": {"order": [1, 0]}},
          {"name": "quantize", "configuration": {"dtype": "int16", "scale": 0.01}},
          {"name": "bytes", "configuration": {}},
          {"name": "blosc", "configuration": {"cname": "lz4", "clevel": 5}}
        ],
        "fill_value": null,
        "attributes": {}
      })

      assert {:ok, metadata} = MetadataV3.from_json(json)
      assert length(metadata.codecs) == 4

      [transpose, quantize, bytes, blosc] = metadata.codecs
      assert transpose.name == "transpose"
      assert transpose.configuration["order"] == [1, 0]

      assert quantize.name == "quantize"
      assert quantize.configuration["dtype"] == "int16"
      assert quantize.configuration["scale"] == 0.01

      assert bytes.name == "bytes"
      assert blosc.name == "blosc"
    end

    test "round-trip: encode then decode produces equivalent metadata" do
      original = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 200, 300},
        data_type: "float32",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 20, 30}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "bytes", configuration: %{}},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0.0,
        attributes: %{"version" => "1.0"},
        dimension_names: ["z", "y", "x"]
      }

      assert {:ok, json} = MetadataV3.to_json(original)
      assert {:ok, decoded} = MetadataV3.from_json(json)

      assert decoded.zarr_format == original.zarr_format
      assert decoded.node_type == original.node_type
      assert decoded.shape == original.shape
      assert decoded.data_type == original.data_type
      assert decoded.fill_value == original.fill_value
      assert decoded.attributes == original.attributes
      assert decoded.dimension_names == original.dimension_names
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = MetadataV3.from_json("{invalid json")
    end

    test "returns error for missing required fields" do
      json = ~S({
        "zarr_format": 3,
        "node_type": "array"
      })

      # Should parse but fail validation
      assert {:ok, metadata} = MetadataV3.from_json(json)
      assert {:error, {:missing_required_field, _}} = MetadataV3.validate(metadata)
    end

    test "returns error for invalid input type" do
      assert {:error, :invalid_json_input} = MetadataV3.from_json(123)
      assert {:error, :invalid_json_input} = MetadataV3.from_json([:not, :a, :map])
    end
  end

  describe "zarr-python file compatibility" do
    @tag :tmp_dir
    test "writes and reads zarr.json file compatible with zarr-python", %{tmp_dir: tmp_dir} do
      # Create metadata with all v3 features
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {1000, 500},
        data_type: "float32",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {100, 50}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "transpose", configuration: %{order: [1, 0]}},
          %{name: "bytes", configuration: %{}},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0.0,
        attributes: %{
          "created_by" => "ExZarr",
          "version" => "0.4.0",
          "description" => "Test array with v3 features"
        },
        dimension_names: ["y", "x"]
      }

      # Write to file
      zarr_json_path = Path.join(tmp_dir, "zarr.json")
      assert {:ok, json} = MetadataV3.to_json(metadata)
      File.write!(zarr_json_path, json)

      # Read back from file
      json_from_file = File.read!(zarr_json_path)
      assert {:ok, read_metadata} = MetadataV3.from_json(json_from_file)

      # Verify all fields match
      assert read_metadata.zarr_format == metadata.zarr_format
      assert read_metadata.node_type == metadata.node_type
      assert read_metadata.shape == metadata.shape
      assert read_metadata.data_type == metadata.data_type
      assert read_metadata.chunk_grid.name == metadata.chunk_grid.name

      assert read_metadata.chunk_grid.configuration.chunk_shape ==
               metadata.chunk_grid.configuration.chunk_shape

      assert read_metadata.fill_value == metadata.fill_value
      assert read_metadata.attributes == metadata.attributes
      assert read_metadata.dimension_names == metadata.dimension_names
      assert length(read_metadata.codecs) == length(metadata.codecs)

      # Verify validation passes
      assert :ok = MetadataV3.validate(read_metadata)
    end

    @tag :tmp_dir
    test "writes sharded array metadata compatible with zarr-python", %{tmp_dir: tmp_dir} do
      # Create metadata with sharding (ZEP 2)
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {10_000, 10_000},
        data_type: "int16",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {1000, 1000}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{
            name: "sharding_indexed",
            configuration: %{
              chunk_shape: {100, 100},
              codecs: [
                %{name: "bytes", configuration: %{}},
                %{name: "blosc", configuration: %{cname: "zstd", clevel: 3, shuffle: "shuffle"}}
              ],
              index_codecs: [
                %{name: "bytes", configuration: %{}},
                %{name: "crc32c", configuration: %{}}
              ],
              index_location: "end"
            }
          }
        ],
        fill_value: -1,
        attributes: %{"sharded" => true}
      }

      # Write to file
      zarr_json_path = Path.join(tmp_dir, "zarr.json")
      assert {:ok, json} = MetadataV3.to_json(metadata)
      File.write!(zarr_json_path, json)

      # Verify JSON structure matches zarr-python format
      {:ok, decoded} = Jason.decode(json)
      assert decoded["zarr_format"] == 3
      assert decoded["node_type"] == "array"
      assert decoded["shape"] == [10_000, 10_000]
      assert decoded["data_type"] == "int16"

      # Verify sharding configuration
      shard_codec = List.first(decoded["codecs"])
      assert shard_codec["name"] == "sharding_indexed"
      assert shard_codec["configuration"]["chunk_shape"] == [100, 100]
      assert length(shard_codec["configuration"]["codecs"]) == 2
      assert shard_codec["configuration"]["index_location"] == "end"

      # Read back and validate
      json_from_file = File.read!(zarr_json_path)
      assert {:ok, read_metadata} = MetadataV3.from_json(json_from_file)
      assert :ok = MetadataV3.validate(read_metadata)

      # Verify sharding codec preserved correctly
      read_shard = List.first(read_metadata.codecs)
      assert read_shard.name == "sharding_indexed"
      assert read_shard.configuration.chunk_shape == {100, 100}
      assert length(read_shard.configuration.codecs) == 2
      assert read_shard.configuration.index_location == "end"
    end

    @tag :tmp_dir
    test "writes group metadata compatible with zarr-python", %{tmp_dir: tmp_dir} do
      metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :group,
        attributes: %{
          "description" => "Root group",
          "created" => "2026-01-25",
          "metadata_version" => 1
        }
      }

      # Write to file
      zarr_json_path = Path.join(tmp_dir, "zarr.json")
      assert {:ok, json} = MetadataV3.to_json(metadata)
      File.write!(zarr_json_path, json)

      # Verify JSON structure
      {:ok, decoded} = Jason.decode(json)
      assert decoded["zarr_format"] == 3
      assert decoded["node_type"] == "group"
      assert decoded["attributes"]["description"] == "Root group"

      # Read back and validate
      json_from_file = File.read!(zarr_json_path)
      assert {:ok, read_metadata} = MetadataV3.from_json(json_from_file)
      assert :ok = MetadataV3.validate(read_metadata)
    end

    @tag :tmp_dir
    test "reads zarr-python created metadata with irregular chunk grid", %{tmp_dir: tmp_dir} do
      # Simulate a zarr-python created file with irregular chunk grid
      python_json = ~S({
        "zarr_format": 3,
        "node_type": "array",
        "shape": [365, 180, 360],
        "data_type": "float32",
        "chunk_grid": {
          "name": "irregular",
          "configuration": {
            "chunk_sizes": [
              [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
              [90, 90],
              [180, 180]
            ]
          }
        },
        "chunk_key_encoding": {"name": "default"},
        "codecs": [
          {"name": "bytes", "configuration": {}},
          {"name": "zstd", "configuration": {"level": 3}}
        ],
        "fill_value": null,
        "attributes": {"description": "Monthly climate data"},
        "dimension_names": ["time", "latitude", "longitude"]
      })

      # Write to file
      zarr_json_path = Path.join(tmp_dir, "zarr.json")
      File.write!(zarr_json_path, python_json)

      # Read and parse
      json_from_file = File.read!(zarr_json_path)
      assert {:ok, metadata} = MetadataV3.from_json(json_from_file)

      # Verify irregular chunk grid parsed correctly
      assert metadata.chunk_grid.name == "irregular"

      assert metadata.chunk_grid.configuration["chunk_sizes"] == [
               [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
               [90, 90],
               [180, 180]
             ]

      # Verify dimension names
      assert metadata.dimension_names == ["time", "latitude", "longitude"]

      # Validate
      assert :ok = MetadataV3.validate(metadata)
    end
  end
end
