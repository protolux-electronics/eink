# EInk

An Elixir library for driving E-Ink (Electronic Paper Display) screens. This library provides high-level abstractions for controlling E-Ink displays through SPI communication, with built-in support for multiple display controllers and integrated image processing capabilities.

## Features

- **Multiple Controller Support**: Built-in drivers for UC8179 and UC8276 controllers
- **Full & Partial Refresh**: Support for both full screen updates and fast partial refresh modes
- **Integrated Image Processing**: Powered by a Rust NIF for high-performance dithering, resizing, and grayscale conversion
- **Hardware Abstraction**: Clean driver interface for easy extension to additional controllers
- **SPI Communication**: Efficient communication using [Elixir Circuits](https://github.com/elixir-circuits) (Circuits.SPI and Circuits.GPIO)

## Supported Hardware

### Display Controllers

- **UC8179**: Typically found in larger displays (7.5", 5.83")
  - Resolution: 800x600
  - Partial refresh support
  
- **UC8276**: Common in medium-sized displays (4.2")
  - Resolution: 400x300
  - Partial refresh support

### Compatible Display Brands

This library works with E-Ink displays from manufacturers using the supported controllers, including:
- Waveshare e-Paper displays
- GoodDisplay e-Paper modules
- Other displays using UC8179 or UC8276 controllers

## Architecture

EInk uses a hybrid architecture combining Elixir and Rust:

- **Elixir Drivers** (`lib/eink/driver/`): Handle SPI communication, display initialization, and command sequences using [Elixir Circuits](https://github.com/elixir-circuits)
- **Rust NIF** (via `dither` dependency): Provides high-performance image processing (dithering, resizing, grayscale conversion)

The Rust NIF is **precompiled** using `rustler_precompiled`, so you don't need the Rust toolchain installed. The correct binary for your platform is automatically downloaded during compilation.

## Installation

Add `eink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:eink, "~> 0.1.0"}
  ]
end
```

## Usage

### Basic Example

```elixir
# Initialize the display driver with hardware configuration
{:ok, display} = EInk.new(EInk.Driver.UC8276, [
  spi_device: "spidev0.0",
  dc_pin: 25,      # Data/Command pin
  reset_pin: 17,   # Reset pin
  busy_pin: 24     # Busy signal pin
])

# Clear the screen to white
EInk.clear(display, :white)

# Load and process an image
{:ok, image} = Dither.load("path/to/image.png")

# Get display capabilities
%{width: width, height: height} = EInk.Driver.UC8276.capabilities()

# Resize image to match display resolution
{:ok, image} = Dither.resize(image, width, height)

# Convert to grayscale
{:ok, image} = Dither.grayscale(image)

# Apply dithering for 1-bit black and white display
{:ok, image} = Dither.dither(image, algorithm: :sierra, bit_depth: 1)

# Convert to raw binary format
{:ok, raw_data} = Dither.to_raw(image)

# Draw to the display with full refresh
EInk.draw(display, raw_data, refresh_type: :full)
```

### Partial Refresh

For faster updates on supported displays:

```elixir
# Draw with partial refresh (faster, but may have ghosting)
EInk.draw(display, raw_data, refresh_type: :partial)
```

### Dithering Algorithms

The `Dither` library supports multiple algorithms:

- `:floyd_steinberg` - Classic error diffusion (good general-purpose)
- `:sierra` - Sierra-3 algorithm (default, good quality)
- `:atkinson` - Atkinson dithering (high contrast)
- `:stucki` - Stucki algorithm (smooth gradients)
- `:burkes` - Burkes algorithm
- `:jarvis` - Jarvis-Judice-Ninke algorithm

Example:

```elixir
{:ok, dithered} = Dither.dither(image, algorithm: :floyd_steinberg, bit_depth: 1)
```

## Hardware Configuration

### Raspberry Pi Example

When connecting an E-Ink display to a Raspberry Pi:

1. **Enable SPI**: Run `sudo raspi-config` and enable SPI under Interface Options
2. **Connect the display**:
   - VCC → 3.3V
   - GND → Ground
   - DIN → MOSI (GPIO 10)
   - CLK → SCLK (GPIO 11)
   - CS → CE0 (GPIO 8)
   - DC → GPIO 25 (configurable)
   - RST → GPIO 17 (configurable)
   - BUSY → GPIO 24 (configurable)

3. **Configure in your code**:

```elixir
{:ok, display} = EInk.new(EInk.Driver.UC8276, [
  spi_device: "spidev0.0",  # Use spidev0.1 for CE1
  dc_pin: 25,
  reset_pin: 17,
  busy_pin: 24
])
```

## Display Drivers

### Creating a Custom Driver

To support additional display controllers, implement the `EInk.Driver` behavior:

```elixir
defmodule EInk.Driver.MyController do
  use EInk.Driver, 
    width: 640, 
    height: 384, 
    palette: :bw, 
    partial_refresh: true

  @impl EInk.Driver
  def new(opts), do: {:ok, state}

  @impl EInk.Driver
  def reset(state), do: {:ok, state}

  @impl EInk.Driver
  def init(state, _opts), do: {:ok, state}

  @impl EInk.Driver
  def draw(state, image, opts), do: {:ok, state}

  @impl EInk.Driver
  def sleep(state), do: {:ok, state}

  @impl EInk.Driver
  def wake(state), do: {:ok, state}
end
```

## Dependencies

This library depends on:

- **[circuits_spi](https://github.com/elixir-circuits/circuits_spi)** (~> 2.0) - SPI communication with the display controller
- **[circuits_gpio](https://github.com/elixir-circuits/circuits_gpio)** (~> 2.0) - GPIO pin control for data/command, reset, and busy signals
- **[dither](https://github.com/protolux-electronics/dither)** (~> 0.1) - Rust NIF for high-performance image processing (precompiled, no Rust toolchain required)

## Platform Support

The precompiled NIF binaries support the following platforms:

- Linux (x86_64, aarch64, armv7, arm)
- macOS (x86_64, Apple Silicon)
- Windows (x86_64)
- FreeBSD (x86_64)

For other platforms, you can compile from source by setting the `DITHER_BUILD` environment variable:

```bash
DITHER_BUILD=1 mix deps.compile dither
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Credits

- **Hardware Communication**: Built on [Elixir Circuits](https://github.com/elixir-circuits) - a suite of libraries for interfacing with hardware
  - [Circuits.SPI](https://github.com/elixir-circuits/circuits_spi) for SPI communication
  - [Circuits.GPIO](https://github.com/elixir-circuits/circuits_gpio) for GPIO pin control
- **Rust NIF Integration**: [Rustler](https://github.com/rusterlium/rustler) enables seamless Elixir-Rust interop
- **Image Dithering**: Powered by the [`dither`](https://gitlab.com/efronlicht/dither) library by Efron Licht
- **Precompiled NIFs**: [RustlerPrecompiled](https://github.com/philss/rustler_precompiled) eliminates the need for Rust toolchain installation
