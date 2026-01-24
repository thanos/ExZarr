[
  # Allow contract_supertype warnings - these are intentional for forward compatibility
  {"lib/ex_zarr.ex", :contract_supertype},
  {"lib/ex_zarr/array.ex", :contract_supertype},
  {"lib/ex_zarr/codecs.ex", :contract_supertype},
  {"lib/ex_zarr/storage/backend/ets.ex", :contract_supertype},

  # Pattern match and coverage warnings - false positives from conditional compilation
  {"lib/ex_zarr/codecs.ex", :pattern_match},
  {"lib/ex_zarr/codecs.ex", :pattern_match_cov},
  {"lib/ex_zarr/codecs/compression_config.ex", :pattern_match_cov},
  {"lib/ex_zarr/codecs/registry.ex", :pattern_match_cov},
  {"lib/ex_zarr/storage/backend/mongo_gridfs.ex", :pattern_match},

  # Callback arg type mismatches - behavior signatures are intentionally flexible
  {"lib/ex_zarr/storage/backend/azure_blob.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/ets.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/gcs.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/mnesia.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/mock.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/mongo_gridfs.ex", :callback_arg_type_mismatch},
  {"lib/ex_zarr/storage/backend/s3.ex", :callback_arg_type_mismatch},

  # Unmatched returns - intentional for Mnesia transactions
  {"lib/ex_zarr/storage/backend/mnesia.ex", :unmatched_return}
]
