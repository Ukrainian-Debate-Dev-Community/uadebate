defmodule Dfu.MixProject do
  use Mix.Project

  # NGO cabinet (dfu.uadebate.com) - digital post, cases, votes
  # (Danish document-handling model). Depends on core and cab
  # (identity/SSO) from the cab submodule; uadebate above aggregates its
  # public subset.
  def project do
    [
      app: :dfu,
      version: "0.4.3",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:core, path: "../../cab/apps/core", env: Mix.env()},
      {:cab, path: "../../cab/apps/cab", env: Mix.env()}
    ]
  end
end
