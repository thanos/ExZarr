defmodule ExZarr.Application do
  @moduledoc """
  ExZarr application module.

  Starts the supervision tree including the codec registry.
  """
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.debug("Starting ExZarr application")

    children = [
      # Codec registry for managing built-in and custom codecs
      {ExZarr.Codecs.Registry, []}
    ]

    opts = [strategy: :one_for_one, name: ExZarr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
