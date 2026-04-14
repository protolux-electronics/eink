defmodule EInk.Driver do
  @type state :: any()

  @callback new(keyword()) :: {:ok, state()} | {:error, any()}
  @callback close(state()) :: :ok
  @callback reset(state()) :: {:ok, state()} | {:error, any()}
  @callback init(state(), keyword()) :: {:ok, state()} | {:error, any()}
  @callback draw(state(), binary(), keyword()) :: {:ok, state()} | {:error, any()}
  @callback sleep(state()) :: {:ok, state()} | {:error, any()}
  @callback wake(state()) :: {:ok, state()} | {:error, any()}

  defmacro __using__(_opts) do
    quote do
      @behaviour EInk.Driver
    end
  end
end

