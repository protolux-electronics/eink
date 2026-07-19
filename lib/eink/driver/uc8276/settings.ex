defmodule EInk.Driver.UC8276.Settings do
  @behaviour EInk.Driver.Settings

  import Bitwise

  @impl true
  def get_init(:grayscale, {400, 300}) do
    [
      {0x00, <<0x3F, 0x4D>>},
      {0x01, <<0x03, 0x10, 0x3F, 0x3F, 0x03>>},
      {0x06, <<0x96, 0x96, 0x29>>},
      {0x30, <<0x1A>>},
      {0x61, <<0x01, 0x90, 0x01, 0x2C>>},
      {0x82, <<0x05>>},
      {0x50, <<0x97>>},
      {0x60, <<0x22>>},
      {0xE3, <<0x88>>},
      {0x41, <<0x00>>}
    ]
  end

  def get_init(mode, {400, 300}) when mode in [:full, :fast] do
    [
      {0x00, <<0x3F, 0x4D>>},
      {0x01, <<0x03, 0x10, 0x3F, 0x3F, 0x03>>},
      {0x06, <<0x96, 0x96, 0x29>>},
      {0x30, <<0x09>>},
      {0x61, <<0x01, 0x90, 0x01, 0x2C>>},
      {0x82, <<0x05>>},
      {0x50, <<0x97>>},
      {0x60, <<0x22>>},
      {0xE3, <<0x88>>},
      {0x41, <<0x00>>}
    ]
  end

  def get_init(mode, resolution) do
    raise "[#{__MODULE__}] Mode `#{inspect(mode)}` is not supported for resolution #{inspect(resolution)}"
  end

  @impl true
  def get_lut(:grayscale, _resolution) do
    grayscale_lut([0, 5, 10, 54], 63)
  end

  def get_lut(:full, _resolution) do
    [
      {0x20, <<0x01, 0x14, 0x0A, 0x14, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)},
      {0x21, <<0x01, 0x54, 0x0A, 0x94, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)},
      {0x22, <<0x01, 0x54, 0x0A, 0x94, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)},
      {0x23, <<0x01, 0x94, 0x0A, 0x54, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)},
      {0x24, <<0x01, 0x94, 0x0A, 0x54, 0x00, 0x01, 0x01>> <> :binary.copy(<<0x00>>, 35)}
    ]
  end

  def get_lut(:fast, _resolution) do
    [
      {0x20, <<0x01, 0x14, 0x00, 0x00, 0x00, 0x01, 0x00>> <> :binary.copy(<<0x00>>, 35)},
      {0x21, <<0x01, 0x14, 0x00, 0x00, 0x00, 0x01, 0x00>> <> :binary.copy(<<0x00>>, 35)},
      {0x22, <<0x01, 0x94, 0x00, 0x00, 0x00, 0x01, 0x00>> <> :binary.copy(<<0x00>>, 35)},
      {0x23, <<0x01, 0x54, 0x00, 0x00, 0x00, 0x01, 0x00>> <> :binary.copy(<<0x00>>, 35)},
      {0x24, <<0x01, 0x14, 0x00, 0x00, 0x00, 0x01, 0x00>> <> :binary.copy(<<0x00>>, 35)}
    ]
  end

  def get_lut(mode, resolution) do
    raise "[#{__MODULE__}] Mode `#{inspect(mode)}` is not supported for resolution #{inspect(resolution)}"
  end

  # Level-select bits (top 2 of a phase byte). Empirically on this panel
  # 0x40 drives a pixel toward black, 0x80 toward white; 0x00 holds at GND.
  @to_black 0x40
  @to_white 0x80
  @gnd 0x00

  @doc """
  Builds the 5 grayscale LUT registers from four whiten-frame counts.

  Takes `[black, dark, light, white]` counts (0..63, 150Hz scale) and an optional
  `reset`. Each pixel is driven to black for `reset` frames, then whitened by its
  count (0 stays black, ~50 saturates to white). Returns `{reg, binary}` tuples for
  VCOM (0x20) and the four transition LUTs (0x21..0x24). Semantic form of the
  literals in `get_lut(:grayscale, _)`; apps drive it live via `EInk.set_waveform/2`.
  """
  def grayscale_lut(counts, reset \\ 63)

  def grayscale_lut([black, dark, light, white], reset) do
    pad = :binary.copy(<<0x00>>, 35)
    settle = 0x02
    max_push = Enum.max([black, dark, light, white])

    # VCOM held at DC across the full drive; mids ride the shared reset+whiten.
    whiten = fn n when n in 0..63 -> group(@to_black ||| reset, settle, @to_white ||| n) <> pad end

    [
      {0x20, group(reset, settle, max_push) <> pad},
      {0x21, whiten.(black)},
      {0x22, whiten.(dark)},
      {0x23, whiten.(light)},
      {0x24, whiten.(white)}
    ]
  end

  # One UC8276 LUT group: repeat=1, phase1, settle (GND), phase2, unused, two
  # state repeats. Phase byte = level-select bits ||| frame count.
  defp group(phase1, settle, phase2) do
    <<0x01, phase1, settle, phase2, @gnd, 0x01, 0x01>>
  end
end
