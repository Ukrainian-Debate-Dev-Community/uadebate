defmodule Uadebate.Umbrella.MixProject do
  use Mix.Project

  # uadebate: the public site on top of cab.
  # Layering (deps point down only):
  #
  #   engine (Node, cab/engine) <- core <- cab <- uadebate
  #
  # core and cab come from the cab submodule (opendebate-cab) as path
  # deps; this umbrella holds only uadebate. The `full` release
  # runs cab (4000) and uadebate.com (4001) in one node.
  def project do
    [
      apps_path: "apps",
      version: "0.5.0",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: [],
      releases: releases()
    ]
  end

  defp releases do
    [
      full: [
        applications: [core: :permanent, cab: :permanent, uadebate: :permanent]
      ]
    ]
  end
end
