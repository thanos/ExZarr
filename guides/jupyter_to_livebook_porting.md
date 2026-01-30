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

### Purpose
Establish which notebooks are worth porting and why.

### Canonical Set

**Resource: Zarr Fundamentals**
- Source: zarr-developers/tutorials
- Core concepts: shapes, dtypes, chunks, attributes
- Dependencies (Python): zarr, numpy
- Livebook relevance: High (introductory, zero cloud dependencies)

**Resource: Cloud-Native Geospatial Zarr 2022**
- Source: zarr-developers/tutorials
- Core concepts: S3-backed Zarr, chunk-aware slicing, lazy reads
- Dependencies (Python): zarr, s3fs, xarray, dask
- Livebook relevance: High (cloud + parallelism demonstration)

**Resource: Xarray Introduction to Zarr**
- Source: tutorial.xarray.dev
- Core concepts: consolidated metadata, pyramidal datasets, multi-dimensional slicing
- Dependencies (Python): xarray, fsspec
- Livebook relevance: Medium (concepts port, tooling differs)

**Resource: Earthmover CNG 2025 Workshop**
- Source: earth-mover/workshop-cng-2025-zarr
- Core concepts: GeoTIFF → Zarr, datacubes, Icechunk / versioning
- Dependencies (Python): xarray, rioxarray, icechunk
- Livebook relevance: Medium-High (conceptual port, partial feature parity)

**Resource: Benchmarking Zarr vs Parquet**
- Source: Element84 blog
- Core concepts: retrieval patterns, access locality, performance comparison
- Dependencies (Python): pandas, zarr
- Livebook relevance: Medium (benchmark logic portable, not datasets)

---

## General Porting Template

This template MUST be used for every notebook port.

### Porting Prompt Template

**Purpose:**
State why this notebook is being ported and what the learner should understand at the end.

**Concept Mapping:**
- Explicitly list Python concepts and their Elixir equivalents:
  - NumPy → Nx
  - zarr-python → ExZarr
  - pandas display → Kino.DataTable
  - matplotlib → Kino.VegaLite
  - Dask → Task.async_stream / Flow (if applicable)

**Structural Mapping:**
- Notebook cells → Livebook sections
- Markdown narrative → Livebook markdown blocks
- Setup cell → Mix.install block

**Technical Requirements:**
- Use Mix.install with pinned dependencies.
- Prefer ExZarr :memory backend unless cloud access is the point.
- Avoid hidden global state.
- Use explicit function calls instead of implicit notebook state.

**Pedagogical Requirements:**
- Each Livebook must:
  - introduce concepts before code
  - show intermediate inspection steps
  - include at least one "change a parameter and observe" exercise

**Output Requirements:**
- All code must be Elixir.
- No Python snippets.
- No shell commands unless unavoidable.
- Clear separation between explanation and execution.

**Acceptance Criteria:**
- A reader unfamiliar with Python can complete the notebook.
- Results are observable and inspectable.
- Failures are understandable.

**Stop Condition:**
- End the port with a recap and open questions section.

---

## Porting Prompt: Zarr Fundamentals → Livebook

**Purpose:**
Introduce the Zarr data model using ExZarr and Nx with zero external dependencies.

**Concept Mapping:**
- NumPy arrays → Nx tensors
- zarr.DirectoryStore → ExZarr :memory backend
- z.info → custom ExZarr metadata inspection function

**Required Sections:**
1. Introduction: What problem Zarr solves
2. Creating an array (shape, dtype, chunks)
3. Writing data
4. Reading slices
5. Inspecting metadata
6. Exercise: change chunk size
7. Recap

**Technical Requirements:**
- Use Mix.install([:ex_zarr, :nx, :kino])
- Create a 1000x1000 Nx tensor
- Store using chunked layout
- Provide a helper that formats metadata as a Markdown table

**Visualization:**
- Optional heatmap slice via VegaLite

**Exercise:**
- Change chunk size and observe:
  - number of chunks
  - metadata changes

**Validation Checklist:**
- Mix.install block present
- shape, chunks, dtype correctly mapped
- slicing returns expected values
- metadata readable without spec knowledge
- NO emoji

---

## Common Pitfalls

- **State Management**: Python notebooks often rely on global state. Elixir requires explicit passing.
- **Lazy Evaluation**: NumPy is eager, Nx can be lazy. Make evaluation explicit.
- **Error Handling**: Pattern matching vs try/except requires different pedagogical approach.
- **Visualization**: Matplotlib is interactive in Jupyter. VegaLite specs are declarative.

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
