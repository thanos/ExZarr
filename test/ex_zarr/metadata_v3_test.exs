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
end
