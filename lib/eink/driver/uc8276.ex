defmodule EInk.Driver.UC8276 do
  @moduledoc """
  Driver for UC8276 e-ink display.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias EInk.Driver.UC8276.Settings
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, active_state: nil, border_flag: false}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8276 hardware reset")

    :ok = GPIO.write(state.driver.reset, 0)
    :ok = Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)

    {:ok, %{state | active_state: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8276 init for #{width}x#{height}")

    # Default to :full state
    state = ensure_state(state, :full, {width, height}, opts)

    {:ok, %{state | border_flag: false}}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    mode = Keyword.get(opts, :mode, :full)
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    res = {width, height}

    if state.driver.debug, do: Logger.debug("UC8276 draw mode: #{mode}")

    # Convert %Dither{} to packed binary or planar tuple if needed
    data =
      case image do
        %Dither{} = dither -> EInk.Utils.to_packed_binary(dither, mode, opts)
        binary when is_binary(binary) -> binary
      end

    # Ensure chip is in the correct mode/LUT state
    state = ensure_state(state, mode, res, opts)

    case mode do
      :grayscale ->
        draw_grayscale(state, data, opts)

      _bw_mode ->
        draw_bw(state, data, mode, opts)
    end
  end

  defp draw_bw(state, image, mode, opts) do
    border_flag = Keyword.get(opts, :border_flag, state.border_flag)

    # Border control strategy from TWE0420NQN30-MNG-A0-V0.2.txt
    border_data = if mode == :fast or border_flag, do: 0xD7, else: 0x97
    SpiDriver.write(state.driver, 0x50, <<border_data>>)

    SpiDriver.write(state.driver, 0x13, image)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    SpiDriver.wait_for_busy(state.driver)

    # Update reference buffer for partial updates
    SpiDriver.write(state.driver, 0x10, image)

    {:ok, %{state | border_flag: border_flag}}
  end

  defp draw_grayscale(state, {sram10, sram13}, _opts) do
    SpiDriver.write(state.driver, 0x10, sram10)
    SpiDriver.write(state.driver, 0x13, sram13)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    SpiDriver.wait_for_busy(state.driver)

    {:ok, state}
  end

  defp ensure_state(state, mode, res, opts) do
    # Waveform overrides from EInk.set_waveform win over the packaged defaults.
    init = Keyword.get(opts, :init) || Settings.get_init(mode, res)
    lut = Keyword.get(opts, :lut) || Settings.get_lut(mode, res)

    cond do
      state.active_state == mode ->
        state

      mode == :grayscale or state.active_state in [:grayscale, nil] ->
        # Major mode shift or starting from nil requires full init
        state = if mode == :grayscale, do: elem(reset(state), 1), else: state

        state = apply_commands(state, init)
        state = if lut, do: apply_commands(state, lut), else: state
        %{state | active_state: mode}

      true ->
        # B&W mode shift (:full <-> :fast) usually only requires a LUT update
        # because the underlying hardware init is the same for both.
        state = if lut, do: apply_commands(state, lut), else: state
        %{state | active_state: mode}
    end
  end

  defp apply_commands(state, commands) do
    for {reg, data} <- commands do
      :ok = SpiDriver.write(state.driver, reg, data)
    end

    state
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8276 entering deep sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8276 waking up")

    reset(state)
  end
end
