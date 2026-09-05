defmodule Aludel.Interfaces.DocumentConverter.Adapters.ImagemagickTest do
  use ExUnit.Case, async: true

  alias Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick

  @png_header <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>

  setup do
    root = temporary_root!()
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "uses a private workspace and passes bounded conversion arguments", %{root: root} do
    executable = executable!(root, "success", success_script(true))

    assert {:ok, @png_header <> workspace} =
             Imagemagick.convert_pdf_to_png("%PDF-1.4\ntest", options(executable, root))

    audit = root |> Path.join("audit.txt") |> File.read!() |> String.split("\n", trim: true)

    assert [^workspace, "700", "600", temporary_workspace | arguments] = audit
    assert Path.basename(temporary_workspace) == Path.basename(workspace)
    assert Enum.take(arguments, length(resource_arguments())) == resource_arguments()
    assert Enum.at(arguments, -3) == Path.join(temporary_workspace, "input.pdf[0]")
    assert Enum.at(arguments, -2) == "-flatten"
    assert Enum.at(arguments, -1) == Path.join(temporary_workspace, "output.png")
    refute File.exists?(workspace)
  end

  test "concurrent conversions use distinct workspaces and clean both", %{root: root} do
    executable = executable!(root, "concurrent", success_script(false))

    workspaces =
      1..2
      |> Task.async_stream(
        fn _index ->
          assert {:ok, @png_header <> workspace} =
                   Imagemagick.convert_pdf_to_png(
                     "%PDF-1.4\ntest",
                     options(executable, root)
                   )

          workspace
        end,
        ordered: false
      )
      |> Enum.map(fn {:ok, workspace} -> workspace end)

    assert length(Enum.uniq(workspaces)) == 2
    refute Enum.any?(workspaces, &File.exists?/1)
  end

  test "preserves unrelated exit messages for a caller that traps exits", %{root: root} do
    executable = executable!(root, "linked-exits", "sleep 0.2\n#{success_script(false)}")
    original_trap_exit = Process.flag(:trap_exit, true)

    try do
      normal_pid =
        spawn_link(fn ->
          Process.sleep(50)
        end)

      abnormal_pid =
        spawn_link(fn ->
          Process.sleep(50)
          exit(:unrelated_failure)
        end)

      assert {:ok, @png_header <> _workspace} =
               Imagemagick.convert_pdf_to_png(
                 "%PDF-1.4\ntest",
                 options(executable, root)
               )

      assert_received {:EXIT, ^normal_pid, :normal}
      assert_received {:EXIT, ^abnormal_pid, :unrelated_failure}
    after
      Process.flag(:trap_exit, original_trap_exit)
    end
  end

  test "rejects oversized input before creating files or running a command", %{root: root} do
    executable = executable!(root, "marker", marker_script())

    assert {:error, {:input_too_large, 5, 4}} =
             Imagemagick.convert_pdf_to_png(
               "12345",
               options(executable, root, max_input_bytes: 4)
             )

    refute File.exists?(Path.join(root, "invoked"))
    assert no_conversion_directories?(root)
  end

  test "rejects oversized output without retaining the workspace", %{root: root} do
    executable = executable!(root, "large-output", large_output_script(32))

    assert {:error, {:output_too_large, 32, 16}} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(executable, root, max_output_bytes: 16)
             )

    assert no_conversion_directories?(root)
  end

  test "times out and kills a TERM-resistant descendant process", %{root: root} do
    descendant_pid_file = Path.join(root, "descendant.pid")

    executable =
      executable!(
        root,
        "blocked-tree",
        """
        trap '' TERM
        /bin/sh -c 'trap "" TERM; echo $$ > "$1"; while :; do sleep 1; done' child "$PWD/../descendant.pid" &
        while [ ! -s "$PWD/../descendant.pid" ]; do sleep 0.01; done
        wait
        """
      )

    on_exit(fn -> kill_recorded_process(descendant_pid_file) end)
    started_at = System.monotonic_time(:millisecond)

    assert {:error, {:conversion_timeout, 500}} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(executable, root, timeout_ms: 500)
             )

    elapsed = System.monotonic_time(:millisecond) - started_at
    assert elapsed < 2_000
    descendant_pid = descendant_pid_file |> File.read!() |> String.trim() |> String.to_integer()
    assert wait_until_stopped(descendant_pid)
    assert no_conversion_directories?(root)
  end

  test "bounds failure diagnostics and removes its workspace", %{root: root} do
    executable =
      executable!(root, "failure", "printf '1234567890abcdefghijklmnopqrstuvwxyz' >&2\nexit 7\n")

    assert {:error, {:conversion_failed, 7, output}} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(executable, root, max_diagnostic_bytes: 16)
             )

    assert output == "1234567890abcdef"
    assert no_conversion_directories?(root)
  end

  test "rejects invalid density and timeout values before execution", %{root: root} do
    executable = executable!(root, "invalid-options", marker_script())

    for invalid_options <- [
          [density: 0],
          [density: 301],
          [density: "150"],
          [timeout_ms: 99],
          [timeout_ms: 60_001]
        ] do
      assert {:error, :invalid_options} =
               Imagemagick.convert_pdf_to_png(
                 "%PDF-1.4\ntest",
                 options(executable, root, invalid_options)
               )
    end

    refute File.exists?(Path.join(root, "invoked"))
    assert no_conversion_directories?(root)
  end

  test "rejects malformed option lists", %{root: root} do
    executable = executable!(root, "malformed-options", marker_script())

    assert {:error, :invalid_options} =
             Imagemagick.convert_pdf_to_png("%PDF-1.4\ntest", [executable, root])

    refute File.exists?(Path.join(root, "invoked"))
    assert no_conversion_directories?(root)
  end

  test "rejects a successful command that does not create a regular output file", %{root: root} do
    executable = executable!(root, "missing-output", "exit 0\n")

    assert {:error, :output_missing} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(executable, root)
             )

    assert no_conversion_directories?(root)
  end

  test "rejects output without a PNG signature", %{root: root} do
    executable =
      executable!(
        root,
        "invalid-output",
        "last=''\nfor argument in \"$@\"; do last=\"$argument\"; done\nprintf 'not a png' > \"$last\"\n"
      )

    assert {:error, :invalid_output} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(executable, root)
             )

    assert no_conversion_directories?(root)
  end

  test "returns a stable error for an unavailable configured executable", %{root: root} do
    assert {:error, :executable_not_found} =
             Imagemagick.convert_pdf_to_png(
               "%PDF-1.4\ntest",
               options(Path.join(root, "missing"), root)
             )

    assert no_conversion_directories?(root)
  end

  defp temporary_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        "aludel-imagemagick-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)
    root
  end

  defp executable!(root, name, body) do
    path = Path.join(root, name)
    File.write!(path, "#!/bin/sh\nset -eu\n#{body}")
    File.chmod!(path, 0o700)
    path
  end

  defp options(executable, root, overrides \\ []) do
    Keyword.merge(
      [executable: executable, temporary_directory: root, timeout_ms: 5_000],
      overrides
    )
  end

  defp success_script(write_audit?) do
    audit =
      if write_audit? do
        """
        mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
        {
          pwd
          mode .
          mode "$input"
          printf '%s\\n' "$MAGICK_TEMPORARY_PATH"
          printf '%s\\n' "$@"
        } > "$PWD/../audit.txt"
        """
      else
        ""
      end

    """
    last=''
    for argument in "$@"; do
      last="$argument"
      case "$argument" in
        *'[0]') input=${argument%[[]0[]]} ;;
      esac
    done
    #{audit}
    printf '\\211PNG\\r\\n\\032\\n' > "$last"
    printf '%s' "$PWD" >> "$last"
    """
  end

  defp marker_script do
    "touch \"$PWD/../invoked\"\nexit 1\n"
  end

  defp large_output_script(bytes) do
    "last=''\nfor argument in \"$@\"; do last=\"$argument\"; done\ndd if=/dev/zero of=\"$last\" bs=#{bytes} count=1 2>/dev/null\n"
  end

  defp resource_arguments do
    [
      "-limit",
      "width",
      "4096",
      "-limit",
      "height",
      "4096",
      "-limit",
      "area",
      "16MP",
      "-limit",
      "memory",
      "128MiB",
      "-limit",
      "map",
      "256MiB",
      "-limit",
      "disk",
      "512MiB",
      "-limit",
      "file",
      "64",
      "-limit",
      "thread",
      "2",
      "-limit",
      "time",
      "5",
      "-density",
      "150"
    ]
  end

  defp no_conversion_directories?(root) do
    root
    |> File.ls!()
    |> Enum.all?(&(not String.starts_with?(&1, "aludel-pdf-")))
  end

  defp wait_until_stopped(_pid, attempts \\ 50)

  defp wait_until_stopped(_pid, 0) do
    false
  end

  defp wait_until_stopped(pid, attempts) do
    if process_alive?(pid) do
      Process.sleep(20)
      wait_until_stopped(pid, attempts - 1)
    else
      true
    end
  end

  defp kill_recorded_process(pid_file) do
    with {:ok, contents} <- File.read(pid_file),
         {pid, ""} <- contents |> String.trim() |> Integer.parse(),
         true <- process_alive?(pid) do
      System.cmd(kill_executable(), ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
    else
      _error -> :ok
    end
  end

  defp process_alive?(pid) do
    case System.cmd(kill_executable(), ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp kill_executable do
    System.find_executable("kill") || raise "kill executable is required for this test"
  end
end
