defmodule Aludel.ReleasePrepScriptTest do
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/aludel_release_prep.exs", __DIR__)

  test "prepares package metadata and release notes from commits since the previous tag" do
    repo = temporary_repo!()
    notes_file = Path.join(repo, "release-notes.md")

    write_release_files!(repo)
    run_git!(repo, ["add", "."])
    run_git!(repo, ["commit", "-m", "chore: release 0.4.1"])
    run_git!(repo, ["tag", "v0.4.1"])

    File.write!(Path.join(repo, "feature.txt"), "new feature\n")
    run_git!(repo, ["add", "feature.txt"])
    run_git!(repo, ["commit", "-m", "feat: add release automation"])
    commit = repo |> run_git!(["rev-parse", "--short", "HEAD"]) |> String.trim()

    {output, status} =
      System.cmd(
        "elixir",
        [@script, "0.4.2", "--date", "2026-08-15", "--notes-file", notes_file],
        cd: repo,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert File.read!(Path.join(repo, "mix.exs")) =~ ~s(version: "0.4.2")
    assert File.read!(Path.join(repo, "README.md")) =~ ~s({:aludel, "~> 0.4.2"})

    changelog = File.read!(Path.join(repo, "CHANGELOG.md"))
    assert changelog =~ "## [0.4.2] - 2026-08-15"
    assert changelog =~ "- `#{commit}` feat: add release automation"
    assert File.read!(notes_file) =~ "- `#{commit}` feat: add release automation"
  end

  test "rejects a version with a leading v" do
    repo = temporary_repo!()

    {output, status} =
      System.cmd("elixir", [@script, "v0.4.2"],
        cd: repo,
        stderr_to_stdout: true
      )

    assert status == 1
    assert output =~ "Expected a SemVer version without the leading v"
  end

  defp temporary_repo! do
    repo =
      Path.join(
        System.tmp_dir!(),
        "aludel-release-prep-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)

    run_git!(repo, ["init", "-b", "main"])
    run_git!(repo, ["config", "user.name", "Release Test"])
    run_git!(repo, ["config", "user.email", "release-test@example.com"])

    repo
  end

  defp write_release_files!(repo) do
    File.write!(Path.join(repo, "mix.exs"), ~s(version: "0.4.1"\n))
    File.write!(Path.join(repo, "README.md"), ~s({:aludel, "~> 0.4"}\n))

    File.write!(
      Path.join(repo, "CHANGELOG.md"),
      """
      # Changelog

      ## [0.4.1] - 2026-06-15

      ### Changed
      - Previous release
      """
    )
  end

  defp run_git!(repo, args) do
    case System.cmd("git", args,
           cd: repo,
           env: [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_ASKPASS", "true"}],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("git #{Enum.join(args, " ")} failed with #{status}:\n#{output}")
    end
  end
end
