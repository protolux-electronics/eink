defmodule Eink.MixProject do
  use Mix.Project

  def project do
    [
      app: :eink,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_spi, "~> 2.1"},
      {:circuits_gpio, "~> 2.0"}
    ]
  end
end
