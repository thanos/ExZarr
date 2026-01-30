# ExZarr Livebook Gallery

**Executable tutorials for cloud-native, concurrent array data in Elixir**

This gallery is a curated collection of **Elixir Livebooks** demonstrating how to use
**ExZarr** — a Zarr v2–compatible array storage library — to build scalable data systems
for **AI / GenAI, finance, crypto, and scientific workloads**.

The structure and philosophy are inspired by the
[Pangeo Tutorial Gallery](https://gallery.pangeo.io/):
each notebook is **runnable**, **self-contained**, and designed to teach one concept
clearly, while fitting into a larger mental model.

> If you prefer narrative explanations, each major Livebook is paired with a
> Medium-style article under `docs/articles/medium/`.

---

## How to use this gallery

### Run locally (recommended)

From the root of the ExZarr repository:

```bash
mix deps.get
mix compile
mix livebook.server
