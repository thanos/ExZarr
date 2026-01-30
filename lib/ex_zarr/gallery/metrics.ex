defmodule ExZarr.Gallery.Metrics do
  @moduledoc """
  Tiny timing/progress helpers for Livebook tutorials.
  """

  @spec time((-> any())) :: {any(), non_neg_integer()}
  def time(fun) when is_function(fun, 0) do
    t0 = System.monotonic_time()
    out = fun.()
    t1 = System.monotonic_time()
    {out, System.convert_time_unit(t1 - t0, :native, :microsecond)}
  end

  @spec human_us(non_neg_integer()) :: String.t()
  def human_us(us) when us < 1_000, do: "#{us}µs"
  def human_us(us) when us < 1_000_000, do: "#{Float.round(us / 1_000, 2)}ms"
  def human_us(us), do: "#{Float.round(us / 1_000_000, 2)}s"
end
