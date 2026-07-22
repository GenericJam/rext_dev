defmodule RextDev.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/genericjam/rext_dev"

  def project do
    [
      app: :rext_dev,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Dev + agent tooling for rext: mix rext.run and mix rext.connect.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:rext, path: "../rext"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [setup: ["deps.get", "cmd git config core.hooksPath .githooks"]]
  end

  defp package do
    [licenses: ["MIT"], links: %{"GitHub" => @source_url}]
  end

  defp docs do
    [main: "readme", extras: ["README.md"]]
  end
end
