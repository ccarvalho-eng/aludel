defmodule Aludel.MixProject do
  use Mix.Project

  def project do
    [
      app: :aludel,
      version: "0.6.1",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        precommit: :test
      ],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      package: package(),
      description: "Aludel - LLM Eval Workbench for Phoenix applications",
      source_url: "https://github.com/ccarvalho-eng/aludel",
      homepage_url: "https://github.com/ccarvalho-eng/aludel",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "guides/features.md",
          "guides/evaluations.md",
          "guides/embedding.md",
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "LICENSE"
        ],
        groups_for_extras: [
          Guides: [
            "guides/features.md",
            "guides/evaluations.md",
            "guides/embedding.md"
          ],
          Project: ["CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Aludel.Application, []},
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "aludel",
      maintainers: ["Cristiano Carvalho"],
      licenses: ["Apache-2.0"],
      files:
        ~w(lib priv/repo priv/static guides .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        "GitHub" => "https://github.com/ccarvalho-eng/aludel"
      }
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.1"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", only: [:dev, :test], runtime: false},
      {:tailwind, "~> 0.3", only: [:dev, :test], runtime: false},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1,
       only: [:dev, :test]},
      {:req, "~> 0.5"},
      {:req_llm, "~> 1.0"},
      {:nimble_csv, "~> 1.2"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:goth, "~> 1.4"},
      {:google_api_storage, "~> 0.46"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:llm_db, "~> 2026.2", runtime: false},

      # Documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Code quality and testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.2", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind aludel", "esbuild aludel"],
      "assets.deploy": [
        "tailwind aludel --minify",
        "esbuild aludel --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict",
        "sobelow --config .sobelow-conf",
        "test"
      ]
    ]
  end
end
