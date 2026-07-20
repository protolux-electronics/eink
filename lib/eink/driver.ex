# SPDX-FileCopyrightText: 2025 Gus Workman
# SPDX-License-Identifier: Apache-2.0
defmodule EInk.Driver do
  @type state :: any()
  @type capability_key :: :width | :height | :type | :palette | :partial_refresh
  @type capabilities :: %{capability_key() => term()}

  @callback capabilities() :: capabilities()
  @callback new(keyword()) :: {:ok, state()} | {:error, any()}
  @callback reset(state()) :: {:ok, state()} | {:error, any()}
  @callback init(state(), keyword()) :: {:ok, state()} | {:error, any()}
  @callback draw(state(), binary(), keyword()) :: {:ok, state()} | {:error, any()}
  @callback sleep(state()) :: {:ok, state()} | {:error, any()}
  @callback wake(state()) :: {:ok, state()} | {:error, any()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour EInk.Driver
      @capabilities Map.new(opts)

      @impl EInk.Driver
      def capabilities(), do: @capabilities
    end
  end
end
