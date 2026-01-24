# Exclude tests that require external services by default
# To run these tests, use: mix test --include s3 --include gcs --include azure --include mongo
ExUnit.configure(exclude: [:s3, :gcs, :azure, :mongo])

ExUnit.start()
