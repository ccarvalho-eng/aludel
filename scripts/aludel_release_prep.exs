defmodule Aludel.ReleasePrepScript do
  @version_files ["README.md"]
  @git_env [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_ASKPASS", "true"}]

  def main(args) do
    {opts, args, invalid} =
      OptionParser.parse(args,
        strict: [date: :string, from_tag: :string, notes_file: :string, notes_only: :boolean],
        aliases: [d: :date]
      )

    if invalid != [] do
      fail!("Invalid options: #{inspect(invalid)}")
    end

    version = single_version!(args)
    validate_version!(version)

    if opts[:notes_only] do
      write_existing_notes!(version, opts[:notes_file])
    else
      prepare_release!(version, opts)
    end
  end

  defp prepare_release!(version, opts) do
    date = Keyword.get(opts, :date, Date.to_iso8601(Date.utc_today()))
    from_tag = Keyword.get(opts, :from_tag) || previous_version_tag!(version)
    commits_since!(from_tag)
    notes = unreleased_notes!()

    update_mix_version!(version)
    update_install_snippets!(version)

    update_changelog!(version, date, notes)
    write_notes_file(opts[:notes_file], notes)

    IO.puts("""
    Prepared Aludel #{version} release metadata.
    Changelog source: #{from_tag}..HEAD
    """)
  end

  defp write_existing_notes!(version, notes_file) do
    notes = versioned_notes!(version)
    write_notes_file(notes_file, notes)

    IO.puts("Prepared release notes for Aludel #{version}.")
  end

  defp single_version!([version]) do
    version
  end

  defp single_version!(_args) do
    fail!(
      "Expected exactly one version argument, for example: " <>
        "elixir scripts/aludel_release_prep.exs 0.4.2"
    )
  end

  defp validate_version!(version) do
    unless Regex.match?(~r/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/, version) do
      fail!("Expected a SemVer version without the leading v, got: #{inspect(version)}")
    end
  end

  defp previous_version_tag!(version) do
    target_tag = "v#{version}"

    "git"
    |> run_git!(["tag", "--sort=-v:refname", "--merged", "HEAD"])
    |> String.split("\n", trim: true)
    |> Enum.find(fn tag ->
      tag != target_tag and
        Regex.match?(~r/^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/, tag)
    end)
    |> case do
      nil -> fail!("Could not find a previous version tag merged into HEAD")
      tag -> tag
    end
  end

  defp commits_since!(from_tag) do
    "git"
    |> run_git!(["log", "--reverse", "--format=%h%x09%s", "#{from_tag}..HEAD"])
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "\t", parts: 2) do
        [sha, subject] -> {sha, subject}
        [subject] -> {"", subject}
      end
    end)
    |> case do
      [] -> fail!("No commits found since #{from_tag}")
      commits -> commits
    end
  end

  defp run_git!(command, args) do
    case System.cmd(command, args, env: @git_env, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        fail!("git #{Enum.join(args, " ")} failed with #{status}:\n#{output}")
    end
  end

  defp update_mix_version!(version) do
    update_file!("mix.exs", fn body ->
      replace_once!(
        body,
        ~r/version: "\d+\.\d+\.\d+(?:[-+][^"]+)?"/,
        ~s(version: "#{version}"),
        "mix.exs version"
      )
    end)
  end

  defp update_install_snippets!(version) do
    Enum.each(@version_files, fn path ->
      update_file!(path, fn body ->
        replace_all!(
          body,
          ~r/\{:aludel, "~> \d+\.\d+(?:\.\d+(?:[-+][^"]+)?)?"\}/,
          ~s({:aludel, "~> #{version}"}),
          "#{path} install snippet"
        )
      end)
    end)
  end

  defp unreleased_notes! do
    body = File.read!("CHANGELOG.md")

    case Regex.run(~r/^## Unreleased[^\n]*\n(?<notes>.*?)(?=^## \[)/ms, body, capture: ["notes"]) do
      [notes] -> normalize_notes!(notes, "Unreleased section has no entries")
      nil -> fail!("Could not find an Unreleased section before the latest release")
    end
  end

  defp versioned_notes!(version) do
    body = File.read!("CHANGELOG.md")
    escaped_version = Regex.escape(version)

    pattern =
      Regex.compile!(
        "^## \\[#{escaped_version}\\][^\\n]*\\n(?<notes>.*?)(?=^## \\[|\\z)",
        "ms"
      )

    case Regex.run(pattern, body, capture: ["notes"]) do
      [notes] -> normalize_notes!(notes, "Release #{version} has no changelog entries")
      nil -> fail!("Could not find CHANGELOG.md release #{version}")
    end
  end

  defp normalize_notes!(notes, error_message) do
    case String.trim(notes) do
      "" -> fail!(error_message)
      normalized -> normalized <> "\n"
    end
  end

  defp update_changelog!(version, date, notes) do
    update_file!("CHANGELOG.md", fn body ->
      if String.contains?(body, "## [#{version}]") do
        fail!("CHANGELOG.md already has a #{version} section")
      end

      section = """
      ## Unreleased

      ## [#{version}] - #{date}

      #{String.trim_trailing(notes)}

      """

      replace_once!(
        body,
        ~r/^## Unreleased[^\n]*\n.*?(?=^## \[)/ms,
        section,
        "CHANGELOG.md Unreleased section"
      )
    end)
  end

  defp write_notes_file(nil, _notes) do
    :ok
  end

  defp write_notes_file(path, notes) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, notes)
  end

  defp update_file!(path, fun) do
    body = File.read!(path)
    File.write!(path, fun.(body))
  end

  defp replace_once!(body, pattern, replacement, label) do
    if Regex.match?(pattern, body) do
      Regex.replace(pattern, body, fn _match -> replacement end, global: false)
    else
      fail!("Could not find #{label}")
    end
  end

  defp replace_all!(body, pattern, replacement, label) do
    if Regex.match?(pattern, body) do
      Regex.replace(pattern, body, replacement)
    else
      fail!("Could not find #{label}")
    end
  end

  defp fail!(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Aludel.ReleasePrepScript.main(System.argv())
