defmodule GlobalChild.MixProject do
  use Mix.Project

  def project do
    [
      app: :global_child,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "Global Child",
      source_url: "https://github.com/lud/global_child",
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:local_cluster, "~> 1.2", only: :test},
      {:schism, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      description: "Cluster-wide singleton child management",
      licenses: ["MIT"],
      maintainers: ["Ludovic Demblans"],
      links: %{GitHub: "https://github.com/lud/global_child"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
