# Jupyter → Livebook Porting Guide

## Purpose

This document defines structured, repeatable prompt sets for porting existing Zarr Jupyter notebooks into Elixir Livebook (.livemd) format, using ExZarr, Nx, and Kino.

## Audience

Senior engineers and scientific developers entering Zarr from the Elixir ecosystem.

## Assumptions

- Livebook is used for exploration and pedagogy
- Nx replaces NumPy
- ExZarr replaces zarr-python
- Kino and VegaLite replace matplotlib / pandas display
- Dask-style parallelism is replaced by explicit BEAM concurrency

## Global Constraints

- No emojis
- Never commit to GitHub, create branches, PRs, or tags
- Work step-by-step
- Treat all code as illustrative unless explicitly told otherwise
- Language must remain simple, technical, and serious

---

## Notebook Inventory

### Canonical Set

| Resource | Source | Core Concepts | Dependencies (Python) | Livebook Relevance |
|----------|--------|---------------|----------------------|-------------------|
| Zarr Fundamentals | zarr-developers/tutorials | shapes, dtypes, chunks, attributes | zarr, numpy | High (introductory, zero cloud dependencies) |
| Cloud-Native Geospatial Zarr 2022 | zarr-developers/tutorials | S3-backed Zarr, chunk-aware slicing, lazy reads | zarr, s3fs, xarray, dask | High (cloud + parallelism demonstration) |
| Xarray Introduction to Zarr | tutorial.xarray.dev | consolidated metadata, pyramidal datasets, multi-dimensional slicing | xarray, fsspec | Medium (concepts port, tooling differs) |
| Earthmover CNG 2025 Workshop | earth-mover/workshop-cng-2025-zarr | GeoTIFF → Zarr, datacubes, Icechunk / versioning | xarray, rioxarray, icechunk | Medium-High (conceptual port, partial feature parity) |
| Benchmarking Zarr vs Parquet | Element84 blog | retrieval patterns, access locality, performance comparison | pandas, zarr | Medium (benchmark logic portable, not datasets) |

---

## General Porting Template

This template MUST be used for every notebook port.

### Template Structure

#### Purpose
State why this notebook is being ported and what the learner should understand at the end.

#### Concept Mapping
Explicitly list Python concepts and their Elixir equivalents:
- NumPy → Nx
- zarr-python → ExZarr
- pandas display → Kino.DataTable
- matplotlib → Kino.VegaLite
- Dask → Task.async_stream / Flow (if applicable)

#### Structural Mapping
- Notebook cells → Livebook sections
- Markdown narrative → Livebook markdown blocks
- Setup cell → Mix.install block

#### Technical Requirements
- Use Mix.install with pinned dependencies
- Prefer ExZarr :memory backend unless cloud access is the point
- Avoid hidden global state
- Use explicit function calls instead of implicit notebook state

#### Pedagogical Requirements
Each Livebook must:
- Introduce concepts before code
- Show intermediate inspection steps
- Include at least one "change a parameter and observe" exercise

#### Output Requirements
- All code must be Elixir
- No Python snippets
- No shell commands unless unavoidable
- Clear separation between explanation and execution

#### Acceptance Criteria
- A reader unfamiliar with Python can complete the notebook
- Results are observable and inspectable
- Failures are understandable

#### Stop Condition
End the port with a recap and open questions section.

---

## Porting Prompt 1: Zarr Fundamentals

### Purpose
Introduce the Zarr data model using ExZarr and Nx with zero external dependencies.

### Concept Mapping
- NumPy arrays → Nx tensors
- zarr.DirectoryStore → ExZarr :memory backend
- z.info → custom ExZarr metadata inspection function

### Required Sections
1. Introduction: What problem Zarr solves
2. Creating an array (shape, dtype, chunks)
3. Writing data
4. Reading slices
5. Inspecting metadata
6. Exercise: change chunk size
7. Recap

### Technical Requirements
- Use Mix.install([:ex_zarr, :nx, :kino])
- Create a 1000x1000 Nx tensor
- Store using chunked layout
- Provide a helper that formats metadata as a Markdown table

### Visualization
- Optional heatmap slice via VegaLite

### Exercise
Change chunk size and observe:
- Number of chunks
- Metadata changes

### Validation Checklist
- [ ] Mix.install block present
- [ ] shape, chunks, dtype correctly mapped
- [ ] Slicing returns expected values
- [ ] Metadata readable without spec knowledge

---

## Porting Prompt 2: Cloud-Native Geospatial Zarr 2022

### Purpose
Demonstrate cloud-native access patterns and selective chunk fetching.

### Concept Mapping
- s3fs → ExZarr S3 backend or ExAws.S3
- Dask parallelism → Task.async_stream

### Required Sections
1. Cloud object storage and Zarr
2. Opening a remote Zarr store
3. Chunk-aware slicing
4. Parallel reads
5. Aggregation example (mean over time)

### Technical Requirements
- Use Livebook secrets for credentials
- Show configuration without hardcoding secrets
- Use Task.async_stream for parallel chunk reads

### Inspection
Use Kino.inspect to show:
- Which chunks are fetched
- When network calls occur

### Advanced Section
Compute mean across one dimension while streaming chunks

### Validation Checklist
- [ ] Secrets not embedded in code
- [ ] Parallel logic handles failures
- [ ] Numerical results match published reference values

---

## Porting Prompt 3: Xarray Introduction to Zarr

### Purpose
Teach higher-level dataset organization concepts without Xarray.

### Concept Mapping
- Xarray Dataset → Zarr groups + attributes
- Consolidated metadata → group-level metadata access

### Required Sections
1. Groups as datasets
2. Attributes as coordinates / labels
3. Multi-resolution or multi-group layouts
4. Reading subsets

### Technical Requirements
- Use ExZarr groups explicitly
- Simulate coordinates via attributes
- Explain what is lost without Xarray

### Visualization
Table-based inspection of group metadata

### Validation Checklist
- [ ] Group hierarchy is clear
- [ ] Attributes are readable and meaningful
- [ ] Limitations are explicitly stated

---

## Porting Prompt 4: Earthmover CNG 2025 Workshop

### Purpose
Demonstrate datacube-style analysis and chunk-based computation.

### Concept Mapping
- GeoTIFF ingestion → synthetic or preprocessed arrays
- Icechunk versioning → simulated via groups (if unsupported)

### Required Sections
1. What is a datacube
2. Building a 4D Zarr structure
3. Chunk-aware computation
4. Zonal statistics example
5. Future directions (Icechunk, Zarr v3)

### Technical Requirements
- Build a 4D array (time, band, y, x)
- Perform computation chunk-by-chunk
- Explain versioning conceptually if not implemented

### Visualization
VegaLite spatial map or slice

### Validation Checklist
- [ ] Coordinates handled consistently
- [ ] Chunk-level computation is explicit
- [ ] Performance characteristics discussed

---

## Porting Prompt 5: Benchmarking Zarr vs Parquet

### Purpose
Teach how to benchmark access patterns, not to win benchmarks.

### Concept Mapping
- pandas benchmarks → Nx timing + Elixir benchmarking tools
- Parquet comparison → conceptual discussion if Parquet tooling is absent

### Required Sections
1. What is being measured
2. Sequential vs random access
3. Chunk size effects
4. Interpretation of results

### Technical Requirements
- Use synthetic datasets
- Use repeatable timing methodology
- Avoid misleading absolute numbers

### Validation Checklist
- [ ] Benchmarks are reproducible
- [ ] Limitations clearly stated
- [ ] Results interpreted cautiously

---

## Implementation Notes

### When to Use Each Prompt

1. **Zarr Fundamentals**: Start here for all new Zarr users
2. **Cloud-Native Geospatial**: For users working with remote data
3. **Xarray Introduction**: For users coming from scientific Python
4. **Earthmover Workshop**: For geospatial/datacube workflows
5. **Benchmarking**: For performance-sensitive applications

### Common Pitfalls

- **State Management**: Python notebooks often rely on global state. Elixir requires explicit passing.
- **Lazy Evaluation**: NumPy is eager, Nx can be lazy. Make evaluation explicit.
- **Error Handling**: Pattern matching vs try/except requires different pedagogical approach.
- **Visualization**: Matplotlib is interactive in Jupyter. VegaLite specs are declarative.

### Extension Points

Future notebooks may cover:
- Zarr v3 sharding
- Custom codecs
- Distributed writes
- Integration with Apache Arrow
- Time-series specific patterns

---

## Review Checklist

Before implementing a Livebook from these prompts:

- [ ] Confirm target audience understanding level
- [ ] Verify all dependencies are available
- [ ] Check that ExZarr feature parity exists
- [ ] Ensure examples are self-contained
- [ ] Validate that exercises have clear solutions
- [ ] Test on a clean Livebook instance

---

## References

- [Zarr Python Tutorials](https://zarr.readthedocs.io/en/stable/tutorial.html)
- [Xarray Zarr Integration](https://docs.xarray.dev/en/stable/user-guide/io.html#zarr)
- [Cloud-Optimized Geospatial Formats](https://guide.cloudnativegeo.org/)
- [ExZarr Documentation](https://hexdocs.pm/ex_zarr)
