defmodule EInk.Driver.UC8253C do
  @moduledoc """
  Driver for UC8253C e-ink display.
  """
  use EInk.Driver

  alias EInk.Driver.SpiDriver
  alias Circuits.GPIO

  require Logger

  @lut %{
    full: %{
      0x20 => <<0x01, 0x0F, 0x0F, 0x0F, 0x01, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x21 => <<0x01, 0x4F, 0x8F, 0x0F, 0x01, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x22 => <<0x01, 0x0F, 0x8F, 0x0F, 0x01, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x23 => <<0x01, 0x4F, 0x8F, 0x4F, 0x01, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x24 => <<0x01, 0x0F, 0x8F, 0x4F, 0x01, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)
    },
    partial: %{
      0x20 => <<0x01, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x21 => <<0x01, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x22 => <<0x01, 0x8F, 0x01, 0x00, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x23 => <<0x01, 0x4F, 0x01, 0x00, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35),
      0x24 => <<0x01, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)
    },
    five_sec: %{
      0x20 =>
        <<0x01, 0x19, 0x19, 0x19, 0x19, 0x01, 0x01, 0x01, 0x19, 0x19, 0x19, 0x01, 0x01, 0x01>> <>
          :binary.copy(<<0x00>>, 28),
      0x21 =>
        <<0x01, 0x59, 0x99, 0x59, 0x99, 0x01, 0x01, 0x01, 0x59, 0x99, 0x19, 0x01, 0x01, 0x01>> <>
          :binary.copy(<<0x00>>, 28),
      0x22 =>
        <<0x01, 0x59, 0x99, 0x59, 0x99, 0x01, 0x01, 0x01, 0x59, 0x99, 0x19, 0x01, 0x01, 0x01>> <>
          :binary.copy(<<0x00>>, 28),
      0x23 =>
        <<0x01, 0x19, 0x99, 0x59, 0x99, 0x01, 0x01, 0x01, 0x59, 0x99, 0x59, 0x01, 0x01, 0x01>> <>
          :binary.copy(<<0x00>>, 28),
      0x24 =>
        <<0x01, 0x19, 0x99, 0x59, 0x99, 0x01, 0x01, 0x01, 0x59, 0x99, 0x59, 0x01, 0x01, 0x01>> <>
          :binary.copy(<<0x00>>, 28)
    }
  }

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver, boot_flag: false, lut_flag: 0, current_lut: nil}}
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

    {:ok, %{state | boot_flag: false, lut_flag: 0, current_lut: nil}}
  end

  @impl EInk.Driver
  def init(state, opts \\ []) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    if state.driver.debug, do: Logger.debug("UC8253C init")

    SpiDriver.write(state.driver, 0x00, <<0xF3, 0x01>>)
    SpiDriver.write(state.driver, 0x01, <<0x03, 0x10, 0x3F, 0x3F, 0x03>>)
    SpiDriver.write(state.driver, 0x06, <<0x17, 0x37, 0x3D>>)
    SpiDriver.write(state.driver, 0x60, <<0x22>>)
    SpiDriver.write(state.driver, 0x82, <<0x00>>)
    SpiDriver.write(state.driver, 0x30, <<0x09>>)
    SpiDriver.write(state.driver, 0xE3, <<0x88>>)
    SpiDriver.write(state.driver, 0x61, <<0xF0, 0x01, 0x68>>)
    SpiDriver.write(state.driver, 0x50, <<0xB7>>)

    # Clear buffer 0x10
    SpiDriver.write(state.driver, 0x10, :binary.copy(<<0xFF>>, div(width * height, 8)))

    {:ok, state}
  end

  @impl EInk.Driver
  def draw(state, image, opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8253C draw")

    if state.boot_flag do
      SpiDriver.write(state.driver, 0x50, <<0xD7>>)
    end

    SpiDriver.write(state.driver, 0x13, image)

    refresh_type = Keyword.get(opts, :refresh_type, :full)
    state = load_lut(state, refresh_type)

    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, %{state | boot_flag: true}}
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
    # init will be called by GenServer
    {:ok, state}
  end

  defp load_lut(state, type) do
    lut_data = @lut[type] || @lut.full

    SpiDriver.write(state.driver, 0x20, lut_data[0x20])
    SpiDriver.write(state.driver, 0x21, lut_data[0x21])
    SpiDriver.write(state.driver, 0x24, lut_data[0x24])

    {reg22, reg23, new_lut_flag} =
      if state.lut_flag == 0 do
        {0x22, 0x23, 1}
      else
        {0x23, 0x22, 0}
      end

    SpiDriver.write(state.driver, reg22, lut_data[0x22])
    SpiDriver.write(state.driver, reg23, lut_data[0x23])

    %{state | lut_flag: new_lut_flag, current_lut: type}
  end
end
