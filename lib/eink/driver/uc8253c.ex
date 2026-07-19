defmodule EInk.Driver.UC8253C do
  @moduledoc """
  Driver for UC8253C e-ink display.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias EInk.Driver.UC8253C.Settings
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, active_state: nil, active_lut_reg: :reg_0x22}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8253C hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    {:ok, %{state | active_state: nil, active_lut_reg: :reg_0x22}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8253C init")

    state = ensure_state(state, :full, {width, height}, opts)

    # Clear buffer 0x10
    SpiDriver.write(state.driver, 0x10, :binary.copy(<<0xFF>>, div(width * height, 8)))

    {:ok, state}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    mode = Keyword.get(opts, :mode, :full)
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    res = {width, height}

    if state.driver.debug, do: Logger.debug("UC8253C draw mode: #{mode}")

    # Pre-process data
    data =
      case image do
        %Dither{} = dither -> EInk.Utils.to_packed_binary(dither, mode, opts)
        binary when is_binary(binary) -> binary
      end

    # Ensure chip is in the correct mode/LUT state
    previous_state = state.active_state
    state = ensure_state(state, mode, res, opts)

    # Specific UC8253C logic for subsequent refreshes (boot_flag equivalent)
    if previous_state != nil do
      SpiDriver.write(state.driver, 0x50, <<0xD7>>)
    end

    case mode do
      :grayscale ->
        draw_grayscale(state, data, opts)

      _bw_mode ->
        draw_bw(state, data, mode, opts)
    end
  end

  defp draw_bw(state, data, mode, _opts) do
    SpiDriver.write(state.driver, 0x13, data)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    # Update reference buffer for partial updates
    if mode != :grayscale do
      SpiDriver.write(state.driver, 0x10, data)
    end

    {:ok, state}
  end

  defp draw_grayscale(state, {buf10, buf13}, _opts) do
    SpiDriver.write(state.driver, 0x10, buf10)
    SpiDriver.write(state.driver, 0x13, buf13)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, state}
  end

  defp ensure_state(state, mode, res, opts) do
    # Waveform overrides from EInk.set_waveform win over the packaged defaults.
    init = Keyword.get(opts, :init) || Settings.get_init(mode, res)

    cond do
      state.active_state == mode ->
        state

      mode == :grayscale or state.active_state in [:grayscale, nil] ->
        # Major mode shift or starting from nil requires full init
        state = if mode == :grayscale, do: elem(reset(state), 1), else: state

        state = apply_commands(state, init)
        state = apply_lut(state, mode, res, opts)
        %{state | active_state: mode}

      true ->
        # B&W mode shift usually only requires a LUT update
        state = apply_lut(state, mode, res, opts)
        %{state | active_state: mode}
    end
  end

  defp apply_commands(state, commands) do
    for {reg, data} <- commands do
      SpiDriver.write(state.driver, reg, data)
    end

    state
  end

  defp apply_lut(state, mode, resolution, opts) do
    lut_data = Keyword.get(opts, :lut) || Settings.get_lut(mode, resolution)

    if lut_data do
      lut_map = Map.new(lut_data)

      SpiDriver.write(state.driver, 0x20, lut_map[0x20])
      SpiDriver.write(state.driver, 0x21, lut_map[0x21])
      SpiDriver.write(state.driver, 0x24, lut_map[0x24])

      {active_reg_addr, inactive_reg_addr, next_reg} =
        if state.active_lut_reg == :reg_0x22 do
          {0x22, 0x23, :reg_0x23}
        else
          {0x23, 0x22, :reg_0x22}
        end

      SpiDriver.write(state.driver, active_reg_addr, lut_map[0x22])
      SpiDriver.write(state.driver, inactive_reg_addr, lut_map[0x23])

      %{state | active_lut_reg: next_reg}
    else
      state
    end
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8253C sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8253C wake")

    {:ok, state} = reset(state)
    {:ok, state}
  end
end
