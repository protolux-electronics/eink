defmodule EInk.Driver.SpiDriver do
  defstruct [:reset, :busy, :dc, :spi, :debug]

  alias Circuits.GPIO
  alias Circuits.SPI

  @type t() :: %__MODULE__{}

  def open(opts) do
    reset_pin = Keyword.fetch!(opts, :reset_pin)
    busy_pin = Keyword.fetch!(opts, :busy_pin)
    dc_pin = Keyword.fetch!(opts, :dc_pin)
    spi_device = Keyword.fetch!(opts, :spi_device)
    debug = Keyword.get(opts, :debug, false)

    spi_opts =
      opts
      |> Keyword.get(:spi_opts, [])
      |> Keyword.put_new(:mode, 0)
      |> Keyword.put_new(:speed_hz, 100_000)

    {:ok, reset} = GPIO.open(reset_pin, :output, initial_value: 1)
    {:ok, busy} = GPIO.open(busy_pin, :input)
    {:ok, dc} = GPIO.open(dc_pin, :output, initial_value: 0)
    {:ok, spi} = SPI.open(spi_device, spi_opts)

    %__MODULE__{
      reset: reset,
      busy: busy,
      dc: dc,
      spi: spi,
      debug: debug
    }
  end

  @spec write(t(), non_neg_integer(), binary()) :: :ok
  def write(%__MODULE__{} = state, command, data \\ "", _opts \\ []) do
    GPIO.write(state.dc, 0)
    SPI.write!(state.spi, <<command>>)

    if data != "" do
      GPIO.write(state.dc, 1)
      SPI.write!(state.spi, data)
    end

    :ok
  end

  def wait_for_busy(%__MODULE__{} = state, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    polarity = Keyword.get(opts, :polarity, :active_low)

    Stream.repeatedly(fn ->
      Process.sleep(1)
      {GPIO.read(state.busy), polarity}
    end)
    |> Stream.take(timeout)
    |> Enum.reduce_while({:error, :timeout}, fn
      {1, :active_high}, acc -> {:cont, acc}
      {0, :active_low}, acc -> {:cont, acc}
      _value, _acc -> {:halt, :ok}
    end)
  end
end
