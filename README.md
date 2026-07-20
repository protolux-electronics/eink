# EInk

Pure Elixir driver for e-paper displays over SPI. Built on `circuits_spi` and
`circuits_gpio`. Works on Nerves or any Elixir target with SPI/GPIO access.

## Features

* Direct SPI/GPIO control of e-paper controller chips
* Full and fast (no blink) refresh
* Deep sleep and wake
* `EInk.Driver` behaviour for adding new controller chips

## Installation

```elixir
def deps do
  [
    {:eink, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
{:ok, eink} =
  EInk.new(EInk.Driver.UC8276,
    spi_device: "spidev0.0",
    reset_pin: 17,
    busy_pin: 24,
    dc_pin: 25
  )

EInk.clear(eink, :white)
EInk.draw(eink, image_binary)
```

`image_binary` is a 1-bit-per-pixel binary, row-major, sized to the panel's
`width * height`.

## Supported chips

| Chip   | Resolution | Palette | Partial refresh |
| ------ | ---------- | ------- | --------------- |
| UC8179 | 800x600    | B/W     | yes             |
| UC8276 | 400x300    | B/W     | yes             |
