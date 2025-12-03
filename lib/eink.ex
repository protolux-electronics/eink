defmodule EInk do
  @type t() :: %__MODULE__{}

  defstruct [:driver_mod, :driver]

  require Logger

  def new(driver_module, opts \\ []) do
    {:ok, driver} = driver_module.new(opts)

    driver_module.reset(driver)
    driver_module.init(driver)

    {:ok, %__MODULE__{driver: driver, driver_mod: driver_module}}
  end

  @spec clear(t(), :white | :black | :gray) :: :ok | {:error, any()}
  def clear(%__MODULE__{} = eink, color \\ :white, eink_opts \\ []) do
    %{width: w, height: h} = eink.driver_mod.capabilities()

    num_pixels = w * h
    num_bytes = Integer.floor_div(num_pixels, 8)

    data =
      case color do
        :white ->
          :binary.copy(<<0xFF>>, num_bytes)

        :black ->
          :binary.copy(<<0x00>>, num_bytes)

        other ->
          raise "Invalid color `#{other}`. Supported colors are `:white`, `:black`, and `gray`"
      end

    Logger.debug("clearing screen")

    draw(eink, data, eink_opts)
  end

  def draw(eink, image, opts \\ []) do
    eink.driver_mod.draw(eink.driver, image, opts)
  end
end
