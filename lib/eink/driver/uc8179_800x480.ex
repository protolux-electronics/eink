defmodule EInk.Driver.UC8179_800x480 do
  @moduledoc """
  Driver for UC8179 7.5" e-ink display (800x480).
  """
  use EInk.Driver, width: 800, height: 480, palette: :bw, partial_refresh: true

  alias EInk.Driver.SpiDriver
  alias Circuits.GPIO

  require Logger

  @lut %{
    full: %{
      0x20 => <<0x00, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x21 => <<0x60, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x22 => <<0x20, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x23 => <<0x64, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x24 => <<0x24, 0x14, 0x14, 0x14, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36)
    },
    partial: %{
      0x20 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x21 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x22 => <<0x80, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x23 => <<0x40, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36),
      0x24 => <<0x00, 0x14, 0x00, 0x00, 0x00, 0x01>> <> :binary.copy(<<0x00>>, 36)
    }
  }

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, boot_flag: false, current_lut: nil}}
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8179 800x480 hardware reset")

    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(10)
    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | boot_flag: false, current_lut: nil}}
  end

  @impl EInk.Driver
  def init(state, _opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8179 800x480 init")

    SpiDriver.write(state.driver, 0x00, <<0x3F, 0x0D>>)
    SpiDriver.write(state.driver, 0x01, <<0x03, 0x17, 0x3F, 0x3F, 0x03>>)
    SpiDriver.write(state.driver, 0x06, <<0x17, 0x17, 0x3D, 0x3C>>)
    SpiDriver.write(state.driver, 0x30, <<0x09>>)
    SpiDriver.write(state.driver, 0x61, <<0x03, 0x20, 0x01, 0xE0>>)
    SpiDriver.write(state.driver, 0x65, <<0x00, 0x00, 0x00, 0x00>>)
    SpiDriver.write(state.driver, 0x82, <<0x00>>)
    SpiDriver.write(state.driver, 0x50, <<0x29, 0x07>>)
    SpiDriver.write(state.driver, 0x52, <<0x02>>)
    SpiDriver.write(state.driver, 0x60, <<0x22>>)
    SpiDriver.write(state.driver, 0xE3, <<0x88>>)

    # Clear buffer 0x10
    SpiDriver.write(state.driver, 0x10, :binary.copy(<<0xFF>>, div(800 * 480, 8)))

    {:ok, state}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8179 800x480 draw")

    if state.boot_flag do
      SpiDriver.write(state.driver, 0x50, <<0xA9, 0x07>>)
    end

    SpiDriver.write(state.driver, 0x13, image)

    refresh_type = Keyword.get(opts, :refresh_type, :full)
    load_lut(state, @lut[refresh_type] || @lut.full)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | boot_flag: true, current_lut: refresh_type}}
  end

  @impl EInk.Driver
  def sleep(state) do
    if state.driver.debug, do: Logger.debug("UC8179 800x480 sleep")

    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    if state.driver.debug, do: Logger.debug("UC8179 800x480 wake")

    {:ok, state} = reset(state)
    init(state)
  end

  defp load_lut(state, lut) do
    for {reg, lut_data} <- lut do
      SpiDriver.write(state.driver, reg, lut_data)
    end
  end
end
