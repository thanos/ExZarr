# Exclude tests that require external services by default
# These backends require external services, credentials, or special setup:
# - :s3     - AWS S3 (requires credentials)
# - :gcs    - Google Cloud Storage (requires credentials)
# - :azure  - Azure Blob Storage (requires credentials)
# - :mongo  - MongoDB GridFS (requires MongoDB running)
# - :mnesia - Mnesia distributed database (requires Mnesia setup)
# - :python - Python zarr-python integration tests (requires Python + zarr + numpy)
#
# CI runs only self-contained backends: Memory, ETS, Mock, Filesystem, Zip
#
# To run these tests locally:
#   mix test --include s3 --include gcs --include azure --include mongo --include mnesia --include python
ExUnit.configure(exclude: [:s3, :gcs, :azure, :mongo, :mnesia, :python])

ExUnit.start()
