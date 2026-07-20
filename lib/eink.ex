# SPDX-FileCopyrightText: 2025 Gus Workman
# SPDX-FileCopyrightText: 2026 Frank Hunleth
# SPDX-License-Identifier: Apache-2.0
defmodule EInk do
  @moduledoc """
  Top-level API for driving e-paper panels.

  `EInk` wraps a display driver module that implements the `EInk.Driver`
  behaviour (for example `EInk.Driver.UC8179` or `EInk.Driver.UC8276`) and
  exposes a single interface for clearing and drawing to the panel,
  regardless of which controller chip is underneath.

      {:ok, eink} =
        EInk.new(EInk.Driver.UC8276,
          spi_device: "spidev0.0",
          reset_pin: 17,
          busy_pin: 24,
          dc_pin: 25
        )

      EInk.clear(eink, :white)
      EInk.draw(eink, image_binary)
  """

  require Logger

  @type t() :: %__MODULE__{}

  defstruct [:driver_mod, :driver]

  @doc """
  Initializes a display using the given driver module.

  `driver_module` must implement the `EInk.Driver` behaviour. `opts` are
  passed through to the driver's `new/1` callback and typically include
  the GPIO pins and SPI device used to talk to the panel.

  Resets and initializes the panel before returning.
  """
  def new(driver_module, opts \\ []) do
    {:ok, driver} = driver_module.new(opts)

    driver_module.reset(driver)
    driver_module.init(driver)

    {:ok, %__MODULE__{driver: driver, driver_mod: driver_module}}
  end

  @doc """
  Fills the panel with a solid color.

  `color` is `:white` (default) or `:black`. `eink_opts` are passed through
  to `draw/3`, e.g. `refresh_type: :full` or `refresh_type: :partial`.
  """
  @spec clear(t(), :white | :black) :: :ok | {:error, any()}
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

  @doc """
  Draws a raw image to the panel.

  `image` is a 1-bit-per-pixel binary, row-major, sized to the driver's
  `width * height` capability. `opts` are driver-specific; the built-in
  drivers accept `refresh_type: :full | :partial`.
  """
  def draw(eink, image, opts \\ []) do
    eink.driver_mod.draw(eink.driver, image, opts)
  end
end
