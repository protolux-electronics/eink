defmodule EInk.Driver.UC8179 do
  @moduledoc """
  Driver for UC8179 e-ink displays.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias EInk.Driver.UC8179.Settings
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, active_state: nil}}
  end

  @impl EInk.Driver
  def close(state) do
    SpiDriver.close(state.driver)
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8179 hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | active_state: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8179 init for #{width}x#{height}")

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

    if state.driver.debug, do: Logger.debug("UC8179 draw mode: #{mode}")

    # Pre-process data
    data =
      case image do
        %Dither{} = dither -> EInk.Utils.to_packed_binary(dither, mode, opts)
        binary when is_binary(binary) -> binary
      end

    # Ensure chip is in the correct mode/LUT state
    previous_state = state.active_state
    state = ensure_state(state, mode, res, opts)

    # Specific UC8179 logic for subsequent refreshes (boot_flag equivalent)
    # If active_state was already set (not the first draw after reset/init),
    # we might need to set the data interval.
    if previous_state != nil do
      init_commands = Keyword.get(opts, :init) || Settings.get_init(mode, res)

      data_interval =
        if init_commands |> List.keyfind(0x61, 0) == {0x61, <<0x03, 0x20, 0x01, 0xE0>>},
          do: <<0xA9, 0x07>>,
          else: <<0xD7, 0x07>>

      SpiDriver.write(state.driver, 0x50, data_interval)
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

    # Update reference buffer for partial refreshes
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
        # B&W mode shift usually only requires a LUT update
        state = if lut, do: apply_commands(state, lut), else: state
        %{state | active_state: mode}
    end
  end

  defp apply_commands(state, commands) do
    for {reg, data} <- commands do
      SpiDriver.write(state.driver, reg, data)
    end

    state
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8179 sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8179 wake")

    {:ok, state} = reset(state)
    {:ok, state}
  end
end
