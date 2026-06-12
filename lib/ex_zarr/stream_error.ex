defmodule ExZarr.StreamError do
  @moduledoc """
  Raised when `on_error: :halt` is used and a chunk or slice read fails.
  """

  defexception [:message, :index, :reason]

  @impl true
  def exception(opts) do
    index = Keyword.get(opts, :index)
    reason = Keyword.get(opts, :reason)

    message =
      Keyword.get(opts, :message, "stream read failed at #{inspect(index)}: #{inspect(reason)}")

    %__MODULE__{message: message, index: index, reason: reason}
  end
end
