defmodule ExZarr.ZipStorageTest do
  use ExUnit.Case

  describe "Zip storage backend" do
    test "create and save array with zip storage" do
      path = "/tmp/test_zip_#{:rand.uniform(1000000)}.zip"

      try do
        # Create array with zip storage
        {:ok, array} =
          ExZarr.create(
            shape: {100},
            chunks: {20},
            dtype: :int32,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        # Write data
        data =
          for i <- 0..99, into: <<>> do
            <<i::signed-little-32>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

        # Save to zip file
        :ok = ExZarr.save(array, path: path)

        # Verify zip file was created
        assert File.exists?(path)

        # Verify it's a valid zip file
        {:ok, zip_files} = :zip.list_dir(to_charlist(path))
        filenames =
          zip_files
          |> Enum.filter(fn
            {:zip_file, _, _, _, _, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

        assert ".zarray" in filenames
        assert length(filenames) > 1  # Should have metadata + chunks
      after
        File.rm(path)
      end
    end

    test "open and read array from zip storage" do
      path = "/tmp/test_zip_read_#{:rand.uniform(1000000)}.zip"

      try do
        # Create and save array
        {:ok, array} =
          ExZarr.create(
            shape: {50},
            chunks: {10},
            dtype: :float64,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..49, into: <<>> do
            value = i * 1.5
            <<value::float-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
        :ok = ExZarr.save(array, path: path)

        # Open the zip file
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        # Read data back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {50})

        assert read_data == data
      after
        File.rm(path)
      end
    end

    test "zip storage with multiple chunks" do
      path = "/tmp/test_zip_chunks_#{:rand.uniform(1000000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {500},
            chunks: {100},
            dtype: :int64,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..499, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})
        :ok = ExZarr.save(array, path: path)

        # Reopen and read
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {500})

        assert read_data == data

        # Read partial slice crossing chunk boundary
        {:ok, partial} = ExZarr.Array.get_slice(reopened, start: {95}, stop: {105})

        expected =
          for i <- 95..104, into: <<>> do
            <<i::signed-little-64>>
          end

        assert partial == expected
      after
        File.rm(path)
      end
    end

    test "zip storage with filters" do
      path = "/tmp/test_zip_filters_#{:rand.uniform(1000000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {100},
            chunks: {20},
            dtype: :int64,
            filters: [{:delta, [dtype: :int64]}],
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..99, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
        :ok = ExZarr.save(array, path: path)

        # Reopen and verify filters are preserved
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        assert reopened.metadata.filters == [{:delta, [dtype: :int64, astype: :int64]}]

        # Read data back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {100})

        assert read_data == data
      after
        File.rm(path)
      end
    end

    test "zip storage preserves metadata" do
      path = "/tmp/test_zip_metadata_#{:rand.uniform(1000000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200, 150},
            chunks: {50, 30},
            dtype: :float32,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        :ok = ExZarr.save(array, path: path)

        # Reopen and verify metadata
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        assert reopened.metadata.shape == {200, 150}
        assert reopened.metadata.chunks == {50, 30}
        assert reopened.metadata.dtype == :float32
        assert reopened.metadata.zarr_format == 2
      after
        File.rm(path)
      end
    end

    test "zip storage with different dtypes" do
      dtypes = [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64]

      Enum.each(dtypes, fn dtype ->
        path = "/tmp/test_zip_#{dtype}_#{:rand.uniform(1000000)}.zip"

        try do
          {:ok, array} =
            ExZarr.create(
              shape: {10},
              chunks: {10},
              dtype: dtype,
              compressor: :zlib,
              storage: :zip,
              path: path
            )

          # Create appropriate test data for the dtype
          data = case dtype do
            dt when dt in [:int8, :int16, :int32, :int64] ->
              for i <- 0..9, into: <<>> do
                case dt do
                  :int8 -> <<i::signed-little-8>>
                  :int16 -> <<i * 10::signed-little-16>>
                  :int32 -> <<i * 100::signed-little-32>>
                  :int64 -> <<i * 1000::signed-little-64>>
                end
              end

            dt when dt in [:uint8, :uint16, :uint32, :uint64] ->
              for i <- 0..9, into: <<>> do
                case dt do
                  :uint8 -> <<i::unsigned-little-8>>
                  :uint16 -> <<i * 10::unsigned-little-16>>
                  :uint32 -> <<i * 100::unsigned-little-32>>
                  :uint64 -> <<i * 1000::unsigned-little-64>>
                end
              end

            dt when dt in [:float32, :float64] ->
              for i <- 0..9, into: <<>> do
                value = i * 1.5
                case dt do
                  :float32 -> <<value::float-little-32>>
                  :float64 -> <<value::float-little-64>>
                end
              end
          end

          :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
          :ok = ExZarr.save(array, path: path)

          # Reopen and verify
          {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
          {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {10})

          assert read_data == data
        after
          File.rm(path)
        end
      end)
    end
  end
end
