defmodule EInk do
  @moduledoc """
  EInk GenServer that manages the display driver and state.
  """
  use GenServer

  require Logger

  defstruct [:driver_mod, :driver_state, :width, :height, :palette]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def draw(image, opts \\ []) do
    GenServer.call(__MODULE__, {:draw, image, opts})
  end

  def clear(color \\ :white, opts \\ []) do
    GenServer.call(__MODULE__, {:clear, color, opts})
  end

  def sleep() do
    GenServer.call(__MODULE__, :sleep)
  end

  def wake() do
    GenServer.call(__MODULE__, :wake)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_all_env(:eink)
    driver_mod = Keyword.fetch!(config, :driver)
    width = Keyword.fetch!(config, :width)
    height = Keyword.fetch!(config, :height)
    palette = Keyword.get(config, :palette, :bw)
    driver_config = Keyword.get(config, :driver_config, [])

    {:ok, driver_state} = driver_mod.new(driver_config)

    state = %__MODULE__{
      driver_mod: driver_mod,
      driver_state: driver_state,
      width: width,
      height: height,
      palette: palette
    }

    # Initialize the hardware
    {:ok, driver_state} = driver_mod.reset(driver_state)
    {:ok, driver_state} = driver_mod.init(driver_state, config)

    {:ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:draw, image, opts}, _from, state) do
    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, image, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:clear, color, opts}, _from, state) do
    num_pixels = state.width * state.height
    num_bytes = div(num_pixels, 8)

    data =
      case color do
        :white -> :binary.copy(<<0xFF>>, num_bytes)
        :black -> :binary.copy(<<0x00>>, num_bytes)
        other -> raise "Invalid color `#{other}`. Supported colors are `:white` and `:black`"
      end

    Logger.debug("Clearing screen to #{color}")
    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, data, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call(:sleep, _from, state) do
    {:ok, driver_state} = state.driver_mod.sleep(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call(:wake, _from, state) do
    {:ok, driver_state} = state.driver_mod.wake(state.driver_state)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.driver_mod && state.driver_state do
      state.driver_mod.close(state.driver_state)
    end
    :ok
  end
end
