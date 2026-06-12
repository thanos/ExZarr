The livebooks directry should be a curated collection of **Elixir Livebooks** demonstrating how to use
**ExZarr** — a Zarr v3–compatible array storage library — to build scalable data systems
for **AI / GenAI, finance, crypto, and scientific workloads**.

The structure and philosophy are  to be inspired by the
[Pangeo Tutorial Gallery](https://gallery.pangeo.io/):
each notebook is **runnable**, **self-contained**, and designed to teach one concept
clearly, while fitting into a larger mental model.

A good Livebook should:
- Run in under 5 minutes
- Use deterministic or generated data
- Demonstrate one clear idea
- Include a short “Why this matters” section
- Avoid external services unless clearly marked




For  narrative explanations, each major Livebook will be later  paired with a Medium-style article under 
`docs/articles/medium/`. So each major Livebook collection will have a companion article series under:
docs/articles/medium/
  - Livebook → executable, exploratory, concrete
  - Article → narrative, tradeoffs, architectural context
  
Think of the Livebook as the lab, and the article as the lecture.

I want one  you generate the following livebooks:
| | Livebook                               | Description                                            |
| = | -------------------------------------- | ------------------------------------------------------ |
| 00 — Introduction | `00_introduction/00_01_welcome.livemd` | What ExZarr is, what Zarr is, and when *not* to use it |
| 01 — Core Zarr Concepts | `01_core_zarr/01_01_first_zarr_array.livemd`    | Create, write, read, stream, save, and reopen a Zarr array |
| 01 — Core Zarr Concepts| `01_core_zarr/01_02_metadata_and_chunks.livemd` | `.zarray`, `.zattrs`, chunk shapes, and why they matter  and explained Visually |
| 01 — Core Zarr Concepts| `01_core_zarr/01_03_chunk_streaming.livemd`     | Sequential vs parallel chunk streaming                     |
| 01 — Core Zarr Concepts| `02_concurrency/02_01_parallel_reads.livemd`         | Parallel chunk reads with bounded concurrency    |
| 01 — Core Zarr Concepts| `01_core_zarr/01_04_codecs_and_pipelines.livemd` | v2 compressors vs v3 codec pipelines |
| 02 — Concurrency & Performance (Elixir-native) | `02_concurrency/02_01_parallel_reads.livemd`         | Parallel chunk reads with bounded concurrency |
| 02 — Concurrency & Performance (Elixir-native) | `02_concurrency/02_02_safe_concurrent_writes.livemd` | Chunk-level write safety and isolation        |
| 02 — Concurrency & Performance (Elixir-native) | `02_concurrency/02_03_profiling_exzarr.livemd`       | IO vs decode vs scheduling costs              |
| 02 — Concurrency & Performance (Elixir-native) | `02_concurrency/02_04_chunk_shape_laboratory.livemd` | Empirical chunk sizing experiments            |
| 02 — Concurrency & Performance (Elixir-native) | `02_concurrency/02_05_sharding_concepts.livemd`      | Mapping Zarr v3 sharding to Elixir patterns   |


| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_01_zarr_to_nx.livemd`            | Loading Zarr slices into Nx tensors   |
| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_02_streaming_minibatches.livemd` | Chunk-aware batch iterators           |
| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_03_training_from_zarr.livemd`    | Training a small Axon model from Zarr |
| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_04_chunked_training.livemd`      | Training a model from chunked data    |
| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_05_chunked_training_with_validation.livemd` | Training a model from chunked data with validation |
| 03 — Nx & Machine Learning Foundations | `03_nx_ml/03_04_codec_choices_for_ml.livemd` | Codec pipelines for ML workloads (v3-aligned) |
| 04 — AI & GenAI | `04_ai_genai/04_01_embeddings_in_zarr.livemd`           | Embedding matrices: storage layout, chunking strategies                    |
| 04 — AI & GenAI | `04_ai_genai/04_02_multimodel_embeddings.livemd`        | Multiple embedding spaces in one store (CLIP, text, image)                 |
| 04 — AI & GenAI | `04_ai_genai/04_03_chunk_parallel_similarity.livemd`    | Chunk-parallel similarity scan with bounded concurrency                    |
| 04 — AI & GenAI | `04_ai_genai/04_04_rag_dataset_layouts.livemd`          | RAG-friendly layouts: documents, chunks, embeddings, metadata              |
| 04 — AI & GenAI | `04_ai_genai/04_05_prompt_response_cubes.livemd`        | Prompt × response × metric tensors for LLM evaluation                      |
| 04 — AI & GenAI | `04_ai_genai/04_06_llm_eval_regression.livemd`          | LLM evaluation regression store: tracking metrics over time                |
| 04 — AI & GenAI | `04_ai_genai/04_07_tokenized_sequence_packing.livemd`   | Efficient packing of tokenized sequences for training                      |
| 04 — AI & GenAI | `04_ai_genai/04_08_continual_training.livemd`           | Continual training windows: append-only, sliding window datasets           |
| 04 — AI & GenAI | `04_ai_genai/04_09_feature_cache_inference.livemd`      | Feature cache for inference: pre-computed embeddings, activations          |
| 04 — AI & GenAI | `04_ai_genai/04_10_image_tensors_cv.livemd`             | Image tensors for computer vision: batches, channels, spatial dimensions   |
| 04 — AI & GenAI | `04_ai_genai/04_11_audio_spectrogram_cubes.livemd`      | Audio spectrogram cubes: time × frequency × channels                       |
| 04 — AI & GenAI | `04_ai_genai/04_12_rl_replay_buffers.livemd`            | RL replay buffers: state × action × reward tensors with circular updates   |
| 04 — AI & GenAI | `04_ai_genai/04_13_synthetic_dataset_generation.livemd` | Synthetic dataset generation: streaming writes, versioning, metadata       |
| 04 — AI & GenAI | `04_ai_genai/04_14_quantization_experiments.livemd`     | Quantization experiment tracking: model × precision × metric comparisons   |
| 04 — AI & GenAI | `04_ai_genai/04_15_serving_telemetry.livemd`            | Serving telemetry analytics: request × latency × throughput time series    |
| 05 — Finance | `05_finance/05_01_tick_data_cubes.livemd`          | Time × symbol × field tick cubes: efficient storage and retrieval         |
| 05 — Finance | `05_finance/05_02_order_book_tensors.livemd`       | Order book snapshots as tensors: level × side × timestamp                 |
| 05 — Finance | `05_finance/05_03_trade_quote_alignment.livemd`    | Trade / quote alignment: synchronizing multiple data streams              |
| 05 — Finance | `05_finance/05_04_volatility_surface_grids.livemd` | Volatility surface grids: strike × expiry × time cubes                    |
| 05 — Finance | `05_finance/05_05_risk_scenario_cubes.livemd`      | Risk scenario cubes: scenario × factor × portfolio stress testing         |
| 05 — Finance | `05_finance/05_06_pnl_attribution.livemd`          | PnL attribution: multi-dimensional profit/loss decomposition              |
| 05 — Finance | `05_finance/05_07_backtest_cache_replay.livemd`    | Backtest cache replay: storing and retrieving backtest results            |
| 05 — Finance | `05_finance/05_08_feature_engineering.livemd`      | Feature engineering at scale: chunked computation, windowing, aggregation |
| 05 — Finance | `05_finance/05_09_fraud_feature_store.livemd`      | Fraud feature store: real-time and batch feature management               |
| 05 — Finance | `05_finance/05_10_reconciliation_diffs.livemd`     | Reconciliation via array diffs: detecting discrepancies in financial data |
| 05 — Finance | `05_finance/05_11_stress_testing_load.livemd`      | Stress testing query load: parallel access patterns, performance limits   |
| 05 — Finance | `05_finance/05_12_s3_cost_aware_access.livemd`     | S3 cost-aware access: optimizing chunk size and access patterns for cloud |
| 06 — Crypto | `06_crypto/06_01_block_ohlcv_series.livemd`    | Block & OHLCV time series: on-chain events and price data aligned          |
| 06 — Crypto | `06_crypto/06_02_mempool_feature_cubes.livemd` | Mempool feature cubes: transaction characteristics over time                |
| 06 — Crypto | `06_crypto/06_03_mev_outcome_analytics.livemd` | MEV outcome analytics: sandwich attacks, arbitrage, liquidations as tensors |
| 06 — Crypto | `06_crypto/06_04_dex_pool_tensors.livemd`      | DEX pool tensor models: reserves, prices, volumes across pools and chains   |
| 06 — Crypto | `06_crypto/06_05_cross_venue_arb.livemd`       | Cross-venue arbitrage signals: price discrepancies across DEXs and CEXs     |
| 06 — Crypto | `06_crypto/06_06_zk_benchmark_matrices.livemd` | ZK benchmark matrices: prover performance, verification times, proof sizes  |
| 07 — Geospatial & Climate | `07_geospatial/07_01_lat_lon_time_cubes.livemd`      | Lat/lon/time data cubes: spatial × temporal slicing for earth observation      |
| 07 — Geospatial & Climate | `07_geospatial/07_02_cmip_climate_slices.livemd`     | CMIP-style climate slices: multi-model ensemble datasets and analysis patterns |
| 07 — Geospatial & Climate | `07_geospatial/07_03_regional_aggregations.livemd`   | Regional aggregations: zonal statistics, country-level summaries, watersheds   |
| 07 — Geospatial & Climate | `07_geospatial/07_04_kerchunk_virtual_zarr.livemd`   | Kerchunk virtual Zarr reads: reference stores for legacy formats (HDF5, NetCDF) |
| 08 — Bioimaging & Genomics | `08_bio_genomics/08_01_ome_zarr_multiscale.livemd` | OME-Zarr multiscale images: microscopy pyramids with standardized metadata     |
| 08 — Bioimaging & Genomics | `08_bio_genomics/08_02_pyramid_navigation.livemd`   | Pyramid navigation: efficient resolution selection and spatial queries         |
| 08 — Bioimaging & Genomics | `08_bio_genomics/08_03_metadata_schemas.livemd`     | Metadata schemas: OME-Zarr, v3 extensions, and custom biological annotations   |
| 08 — Bioimaging & Genomics | `08_bio_genomics/08_04_vcf_zarr_queries.livemd`     | VCF-Zarr region queries: genomic variant matrices with efficient range lookups |
| 09 — Systems & Infra | `09_systems/09_01_phoenix_zarr_apis.livemd`     | Phoenix APIs backed by Zarr: streaming responses, caching, query optimization     |
| 09 — Systems & Infra | `09_systems/09_02_zarr_feature_store.livemd`    | Zarr as a feature store: online/offline features, versioning, serving patterns    |
| 09 — Systems & Infra | `09_systems/09_03_failure_injection.livemd`     | Failure injection: fault tolerance, retries, circuit breakers for storage backends |
| 09 — Systems & Infra | `09_systems/09_04_versioned_datasets.livemd`    | Versioned dataset design: snapshots, branching, Icechunk-style patterns            |
| 09 — Systems & Infra | `09_systems/09_05_zarr_v3_migration.livemd`     | Zarr v3 migration: v2 to v3 conversion, coexistence strategies, testing approaches |
| 10 — Advanced Topics | `10_advanced/10_01_zarr_compression.livemd` | Zarr compression strategies |
| 10 — Advanced Topics | `10_advanced/10_02_zarr_parallelism.livemd` | Zarr parallelism strategies |
| 10 — Advanced Topics | `10_advanced/10_03_zarr_caching.livemd` | Zarr caching strategies |
| 10 — Advanced Topics | `10_advanced/10_04_zarr_optimization.livemd` | Zarr optimization strategies |
| 10 — Advanced Topics | `10_advanced/10_05_zarr_performance.livemd` | Zarr performance strategies |
| 10 — Advanced Topics | `10_advanced/10_06_zarr_security.livemd` | Zarr security strategies |
| 10 — Advanced Topics | `10_advanced/10_07_zarr_scaling.livemd` | Zarr scaling strategies |
| 10 — Advanced Topics | `10_advanced/10_08_zarr_deployment.livemd` | Zarr deployment strategies |
| 10 — Advanced Topics | `10_advanced/10_09_zarr_monitoring.livemd` | Zarr monitoring strategies |
| 10 — Advanced Topics | `10_advanced/10_10_zarr_testing.livemd` | Zarr testing strategies |
| 10 — Advanced Topics | `10_advanced/10_11_zarr_best_practices.livemd` | Zarr best practices |
| 10 — Advanced Topics | `10_advanced/10_12_zarr_advanced_topics.livemd` | Zarr advanced topics |

Livebooks in `01 — Core Zarr Concepts` should establish the mental model: arrays are logical objects; chunks are the physical unit of IO.
Livebooks in `02 —Concurrency & Performance (Elixir-native)` should highlight why the BEAM is a good fit for Zarr-style workloads and why Zarr + Elixir is not just “Python Zarr rewritten”.
Livebooks in `04 — AI & GenAI` should treat Zarr as data infrastructure for AI, not just storage and a file format.
Livebooks in `05 — Finance` should focus on fast slicing, reproducibility, and scalable analytics.



A good Livebook should:
- Run in under 5 minutes
- Use deterministic or generated data
- Demonstrate one clear idea
- Include a short “Why this matters” section
- Avoid external services unless clearly marked

Each major Livebook will have a companion article under:
docs/articles/medium/
  - Livebook → executable, exploratory, concrete
  - Article → narrative, tradeoffs, architectural context
Think of the Livebook as the lab, and the article as the lecture.
