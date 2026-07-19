defmodule EInk do
  @moduledoc """
  EInk GenServer that manages the display driver and state.
  """
  use GenServer

  require Logger

  defstruct [
    :driver_mod,
    :driver_state,
    :width,
    :height,
    :palette,
    :orientation,
    :dither,
    waveform_overrides: %{}
  ]

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

  def capabilities() do
    GenServer.call(__MODULE__, :capabilities)
  end

  @doc """
  Overrides the init and/or LUT commands for a draw mode until cleared.

  `overrides` is `[init: [{reg, binary}], lut: [{reg, binary}]]` (both keys optional),
  stored per mode and merged into every later draw of that mode. Resets the driver, so
  the next draw pays one full re-init (~1s) — by design, the LUT lives in chip registers
  that only a fresh init reliably reloads. Lets apps calibrate a panel live, e.g. a
  brightness slider feeding `EInk.Driver.UC8276.Settings.grayscale_lut/2`.
  """
  def set_waveform(mode, overrides) do
    GenServer.call(__MODULE__, {:set_waveform, mode, overrides})
  end

  @doc """
  Drops the waveform override for `mode`, restoring defaults.

  Resets the driver like `set_waveform/2`, so the next draw re-inits.
  """
  def clear_waveform(mode) do
    GenServer.call(__MODULE__, {:clear_waveform, mode})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_all_env(:eink)
    driver_mod = Keyword.fetch!(config, :driver)
    width = Keyword.fetch!(config, :width)
    height = Keyword.fetch!(config, :height)
    palette = Keyword.get(config, :palette, :bw)
    orientation = Keyword.get(config, :orientation, 0)
    dither = Keyword.get(config, :dither, true)
    driver_config = Keyword.get(config, :driver_config, [])

    {:ok, driver_state} = driver_mod.new(driver_config)

    state = %__MODULE__{
      driver_mod: driver_mod,
      driver_state: driver_state,
      width: width,
      height: height,
      palette: palette,
      orientation: orientation,
      dither: dither
    }

    # Initialize the hardware
    {:ok, driver_state} = driver_mod.reset(driver_state)

    init_opts = Keyword.merge(config, driver_config)
    {:ok, driver_state} = driver_mod.init(driver_state, init_opts)

    {:ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:draw, image, opts}, _from, state) do
    # Resolve mode: default to :full
    mode = Keyword.get(opts, :mode, :full)

    # Merge state defaults with call-time overrides
    opts =
      [orientation: state.orientation, dither: state.dither]
      |> Keyword.merge(opts)

    # Preprocess image into binary or %Dither{}
    processed =
      case image do
        binary when is_binary(binary) ->
          binary

        {:file, path} ->
          path
          |> Dither.load!()
          |> preprocess_dither(state, opts)

        %Dither{} = dither ->
          preprocess_dither(dither, state, opts)

        other ->
          raise "Unsupported image type for EInk.draw: #{inspect(other)}"
      end

    # Pass mode, width, height and any waveform override for this mode to driver
    opts =
      opts
      |> Keyword.put(:mode, mode)
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)
      |> Keyword.merge(Map.get(state.waveform_overrides, mode, []))

    {:ok, driver_state} = state.driver_mod.draw(state.driver_state, processed, opts)
    {:reply, :ok, %{state | driver_state: driver_state}}
  end

  @impl true
  def handle_call({:clear, color, opts}, _from, state) do
    mode = Keyword.get(opts, :mode, :full)
    num_pixels = state.width * state.height

    # Merge state defaults with call-time overrides
    opts =
      [orientation: state.orientation, dither: state.dither]
      |> Keyword.merge(opts)

    # For clear, we generate raw binaries based on mode
    data =
      case mode do
        :grayscale ->
          # For grayscale, we return a %Dither{} struct so the driver/utils can handle the mapping
          val = if color == :white, do: 255, else: 0
          raw = :binary.copy(<<val>>, num_pixels)
          Dither.from_raw!(raw, state.width, state.height)

        _ ->
          num_bytes = div(num_pixels, 8)
          byte = if color == :white, do: 0xFF, else: 0x00
          :binary.copy(<<byte>>, num_bytes)
      end

    Logger.debug("Clearing screen to #{color} using #{mode} mode")

    opts =
      opts
      |> Keyword.put(:mode, mode)
      |> Keyword.put_new(:width, state.width)
      |> Keyword.put_new(:height, state.height)
      |> Keyword.merge(Map.get(state.waveform_overrides, mode, []))

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
  def handle_call(:capabilities, _from, state) do
    {:reply, %{width: state.width, height: state.height, palette: state.palette}, state}
  end

  @impl true
  def handle_call({:set_waveform, mode, overrides}, _from, state) do
    overrides_map = Map.put(state.waveform_overrides, mode, overrides)

    # reset forces active_state: nil, so the next draw re-inits with the override
    {:ok, driver_state} = state.driver_mod.reset(state.driver_state)
    {:reply, :ok, %{state | waveform_overrides: overrides_map, driver_state: driver_state}}
  end

  @impl true
  def handle_call({:clear_waveform, mode}, _from, state) do
    overrides_map = Map.delete(state.waveform_overrides, mode)

    {:ok, driver_state} = state.driver_mod.reset(state.driver_state)
    {:reply, :ok, %{state | waveform_overrides: overrides_map, driver_state: driver_state}}
  end

  defp preprocess_dither(dither, state, opts) do
    orientation = Keyword.get(opts, :orientation, state.orientation)

    dither
    |> maybe_rotate(orientation)
    |> Dither.resize!(state.width, state.height)
    |> Dither.grayscale!()
  end

  defp maybe_rotate(dither, 0), do: dither

  defp maybe_rotate(dither, orientation) when orientation in [90, 180, 270] do
    Dither.rotate!(dither, orientation)
  end

  @impl true
  def terminate(_reason, state) do
    if state.driver_mod && state.driver_state do
      state.driver_mod.close(state.driver_state)
    end

    :ok
  end
end
