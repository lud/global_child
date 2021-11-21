defmodule GlobalChild.MixProject do
  use Mix.Project

  def project do
    [
      app: :global_child,
      elixir: "~> 1.12",
      version: "0.2.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "GlobalChild",
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
      {:ex_doc, "~> 0.25.5", only: :dev, runtime: false},
      # {:credo, "~> 1.6", only: :dev},
      {:local_cluster, "~> 1.2", only: :test},
      {:schism, "~> 1.0", only: :test}
    ]
  end

  defp docs do
    [main: "GlobalChild"]
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
