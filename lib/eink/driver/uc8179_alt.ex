defmodule EInk.Driver.UC8179Alt do
  @moduledoc """
  Alternative driver for UC8179 (648x480).
  Repurposes the BWR channels for 2-bit grayscale as specified in the 
  manufacturer reference for BWR panels without a red channel.
  """
  use EInk.Driver, width: 648, height: 480, palette: :grayscale2, partial_refresh: false

  alias EInk.Driver.SpiDriver
  alias Circuits.GPIO

  require Logger

  @impl EInk.Driver
  def new(opts \\ []) do
    spi_driver = SpiDriver.open(opts)

    {:ok, %{driver: spi_driver}}
  end

  @impl EInk.Driver
  def reset(state) do
    if state.driver.debug, do: Logger.debug("UC8179Alt hardware reset")

    :ok = GPIO.write(state.driver.reset, 0)
    Process.sleep(100)
    :ok = GPIO.write(state.driver.reset, 1)
    Process.sleep(100)

    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)

    {:ok, state}
  end

  @impl EInk.Driver
  def init(state, _opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8179Alt init")

    # The reference code doesn't specify init commands other than reset.
    # It relies on OTP defaults.
    reset(state)
  end

  @impl EInk.Driver
  def draw(state, image, _opts \\ []) do
    if state.driver.debug, do: Logger.debug("UC8179Alt draw (grayscale2)")

    {buf10, buf13} = split_grayscale(image)

    # Channel 1: BW Data (Reference calls this "old or BW datas")
    SpiDriver.write(state.driver, 0x10, buf10)

    # Channel 2: Grayscale/Red Data (Reference calls this "new or Red data")
    SpiDriver.write(state.driver, 0x13, buf13)

    # Auto Refresh
    SpiDriver.write(state.driver, 0x17, <<0xA5>>)
    :ok = SpiDriver.wait_for_busy(state.driver, polarity: :active_low)
    Process.sleep(100)

    # Deep Sleep
    SpiDriver.write(state.driver, 0x07, <<0xA5>>)

    {:ok, state}
  end

  @impl EInk.Driver
  def sleep(state) do
    # Already enters sleep in draw/3 per reference logic, but for consistency:
    SpiDriver.write(state.driver, 0x07, <<0xA5>>)
    {:ok, state}
  end

  @impl EInk.Driver
  def wake(state) do
    # Wake requires hardware reset on this controller
    reset(state)
  end

  @doc """
  Splits 2-bit grayscale data into two 1-bit buffers.
  
  Mapping (based on manufacturer BWR reference):
  - 0 (Black): buf10=1, buf13=0
  - 1 (Dark Gray): buf10=1, buf13=1 (Maps to 'Red' in BWR)
  - 2 (Light Gray): buf10=1, buf13=1 (Fallback to 'Red')
  - 3 (White): buf10=0, buf13=0
  """
  def split_grayscale(image) do
    # 2 bits per pixel, 4 pixels per byte
    # We need to produce two binaries, each 1 bit per pixel.
    
    do_split(image, <<>>, <<>>)
  end

  defp do_split(<<byte, rest::binary>>, buf10, buf13) do
    # Extract 4 pixels from the byte (MSB first)
    # P0: bits 7-6, P1: bits 5-4, P2: bits 3-2, P3: bits 1-0
    p0 = Bitwise.bsr(byte, 6)
    p1 = Bitwise.band(Bitwise.bsr(byte, 4), 0x03)
    p2 = Bitwise.band(Bitwise.bsr(byte, 2), 0x03)
    p3 = Bitwise.band(byte, 0x03)

    {b10_0, b13_0} = map_pixel(p0)
    {b10_1, b13_1} = map_pixel(p1)
    {b10_2, b13_2} = map_pixel(p2)
    {b10_3, b13_3} = map_pixel(p3)

    # Pack bits into new bytes (Wait, we are processing 4 pixels which is 1/2 of a 1-bit byte)
    # It's easier to process 8 pixels at a time to fill full bytes for buf10/buf13.
    do_split_8(rest, byte, buf10, buf13)
  end

  defp do_split(<<>>, buf10, buf13), do: {buf10, buf13}

  defp do_split_8(<<byte2, rest::binary>>, byte1, buf10, buf13) do
    # Byte 1 (Pixels 0-3)
    p0 = Bitwise.bsr(byte1, 6)
    p1 = Bitwise.band(Bitwise.bsr(byte1, 4), 0x03)
    p2 = Bitwise.band(Bitwise.bsr(byte1, 2), 0x03)
    p3 = Bitwise.band(byte1, 0x03)

    # Byte 2 (Pixels 4-7)
    p4 = Bitwise.bsr(byte2, 6)
    p5 = Bitwise.band(Bitwise.bsr(byte2, 4), 0x03)
    p6 = Bitwise.band(Bitwise.bsr(byte2, 2), 0x03)
    p7 = Bitwise.band(byte2, 0x03)

    {b10_0, b13_0} = map_pixel(p0)
    {b10_1, b13_1} = map_pixel(p1)
    {b10_2, b13_2} = map_pixel(p2)
    {b10_3, b13_3} = map_pixel(p3)
    {b10_4, b13_4} = map_pixel(p4)
    {b10_5, b13_5} = map_pixel(p5)
    {b10_6, b13_6} = map_pixel(p6)
    {b10_7, b13_7} = map_pixel(p7)

    new_b10 = pack_8_bits(b10_0, b10_1, b10_2, b10_3, b10_4, b10_5, b10_6, b10_7)
    new_b13 = pack_8_bits(b13_0, b13_1, b13_2, b13_3, b13_4, b13_5, b13_6, b13_7)

    do_split(rest, buf10 <> <<new_b10>>, buf13 <> <<new_b13>>)
  end

  # If we have an odd number of bytes (unlikely for 648x480), handle tail.
  defp do_split_8(<<>>, byte1, buf10, buf13) do
    # Just process the 4 pixels we have and pad with white (0,0)
    p0 = Bitwise.bsr(byte1, 6)
    p1 = Bitwise.band(Bitwise.bsr(byte1, 4), 0x03)
    p2 = Bitwise.band(Bitwise.bsr(byte1, 2), 0x03)
    p3 = Bitwise.band(byte1, 0x03)
    
    {b10_0, b13_0} = map_pixel(p0)
    {b10_1, b13_1} = map_pixel(p1)
    {b10_2, b13_2} = map_pixel(p2)
    {b10_3, b13_3} = map_pixel(p3)

    new_b10 = pack_8_bits(b10_0, b10_1, b10_2, b10_3, 0, 0, 0, 0)
    new_b13 = pack_8_bits(b13_0, b13_1, b13_2, b13_3, 0, 0, 0, 0)

    {buf10 <> <<new_b10>>, buf13 <> <<new_b13>>}
  end

  defp map_pixel(0), do: {1, 0} # Black
  defp map_pixel(1), do: {1, 1} # Dark Gray
  defp map_pixel(2), do: {1, 1} # Light Gray (Fallback)
  defp map_pixel(3), do: {0, 0} # White
  defp map_pixel(_), do: {0, 0}

  defp pack_8_bits(b0, b1, b2, b3, b4, b5, b6, b7) do
    import Bitwise
    (b0 <<< 7) ||| (b1 <<< 6) ||| (b2 <<< 5) ||| (b3 <<< 4) ||| 
    (b4 <<< 3) ||| (b5 <<< 2) ||| (b6 <<< 1) ||| b7
  end
end
