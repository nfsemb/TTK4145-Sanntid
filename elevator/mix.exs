defmodule Elevator.MixProject do
  use Mix.Project
  @github_url "https://github.com/TTK4145-students-2020/Project15"

  def project do  
    [
        app: :elevator,
        version: "1.0.0",
        elixir: "~> 1.10.2",
        start_permanent: Mix.env() == :prod,
        deps: deps(),
        docs: [
            main: "main",
            extras: ["MAIN.md", "SPEC.md", "TESTHOME.md"]
          ],
        
        name: "elevator",
        description: "An example open source Elixir application.",
        source_url: @github_url,
        homepage_url: @github_url,
        package: [
            maintainers: ["Marius C. K.", "Mads E. B Lysø", "Niels S. Semb"],
            files: ~w(mix.exs lib MAIN.md),
          licenses: ["MIT"],
          links: %{
            "GitHub" => @github_url,
          }
        ]
    ]
    end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
      # mod: {Elevator, [15657]}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 0.8", only: [:dev, :test]},
      {:earmark, "~> 1.4.3", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
