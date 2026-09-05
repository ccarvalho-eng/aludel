defmodule Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick.OutputBuffer do
  @moduledoc false

  defstruct data: "", remaining: 0

  @type t :: %__MODULE__{data: binary(), remaining: non_neg_integer()}

  @spec new(non_neg_integer()) :: t()
  def new(limit) do
    %__MODULE__{remaining: limit}
  end

  @spec append(t(), iodata()) :: t()
  def append(%__MODULE__{remaining: 0} = buffer, _data) do
    buffer
  end

  def append(%__MODULE__{} = buffer, data) do
    chunk =
      data
      |> IO.iodata_to_binary()
      |> binary_part(0, min(buffer.remaining, IO.iodata_length(data)))

    %__MODULE__{
      data: buffer.data <> chunk,
      remaining: buffer.remaining - byte_size(chunk)
    }
  end
end

defmodule Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick do
  @moduledoc """
  Converts the first page of a PDF to PNG with bounded ImageMagick resources.

  Each conversion runs in a private temporary workspace. Input size, output size,
  execution time, ImageMagick resources, and captured diagnostics are limited.
  The converter and its delegates run in a dedicated OS process group that is
  terminated as a unit. The `magick` executable is preferred, with `convert`
  used as a compatibility fallback.
  """

  @behaviour Aludel.Interfaces.DocumentConverter.Behaviour

  alias Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick.OutputBuffer

  require Logger

  @default_density 150
  @minimum_density 72
  @maximum_density 300
  @default_timeout_ms 30_000
  @minimum_timeout_ms 100
  @maximum_timeout_ms 60_000
  @default_max_input_bytes 10 * 1024 * 1024
  @default_max_output_bytes 20 * 1024 * 1024
  @default_max_diagnostic_bytes 16 * 1024
  @termination_confirmation_ms 5_000
  @workspace_attempts 5
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @type error_reason ::
          :executable_not_found
          | :invalid_options
          | :output_missing
          | :invalid_output
          | {:cleanup_failed, File.posix()}
          | {:conversion_crashed, atom(), :internal_error}
          | {:conversion_failed, non_neg_integer(), binary()}
          | {:conversion_io_failed, File.posix()}
          | :conversion_termination_unconfirmed
          | {:conversion_timeout, pos_integer()}
          | {:input_too_large, non_neg_integer(), pos_integer()}
          | {:output_too_large, non_neg_integer(), pos_integer()}
          | {:workspace_unavailable, File.posix()}

  @impl true
  @spec convert_pdf_to_png(binary(), keyword()) :: {:ok, binary()} | {:error, error_reason()}
  def convert_pdf_to_png(pdf_data, options \\ [])

  def convert_pdf_to_png(pdf_data, options) when is_binary(pdf_data) and is_list(options) do
    if Keyword.keyword?(options) do
      with {:ok, settings} <- validate_options(options),
           :ok <- validate_input(pdf_data, settings.max_input_bytes),
           {:ok, executable} <- resolve_executable(settings.executable),
           {:ok, workspace} <- create_workspace(settings.temporary_directory) do
        convert_in_workspace(executable, pdf_data, settings, workspace)
      end
    else
      {:error, :invalid_options}
    end
  end

  def convert_pdf_to_png(_pdf_data, _options) do
    {:error, :invalid_options}
  end

  defp validate_options(options) do
    with {:ok, density} <-
           bounded_integer(
             options,
             :density,
             @default_density,
             @minimum_density,
             @maximum_density
           ),
         {:ok, timeout_ms} <-
           bounded_integer(
             options,
             :timeout_ms,
             @default_timeout_ms,
             @minimum_timeout_ms,
             @maximum_timeout_ms
           ),
         {:ok, max_input_bytes} <-
           bounded_integer(
             options,
             :max_input_bytes,
             @default_max_input_bytes,
             1,
             @default_max_input_bytes
           ),
         {:ok, max_output_bytes} <-
           bounded_integer(
             options,
             :max_output_bytes,
             @default_max_output_bytes,
             1,
             @default_max_output_bytes
           ),
         {:ok, max_diagnostic_bytes} <-
           bounded_integer(
             options,
             :max_diagnostic_bytes,
             @default_max_diagnostic_bytes,
             0,
             @default_max_diagnostic_bytes
           ),
         {:ok, temporary_directory} <- temporary_directory(options),
         {:ok, executable} <- executable_option(options) do
      {:ok,
       %{
         density: density,
         executable: executable,
         max_diagnostic_bytes: max_diagnostic_bytes,
         max_input_bytes: max_input_bytes,
         max_output_bytes: max_output_bytes,
         temporary_directory: temporary_directory,
         timeout_ms: timeout_ms
       }}
    else
      _error -> {:error, :invalid_options}
    end
  end

  defp bounded_integer(options, key, default, minimum, maximum) do
    value = Keyword.get(options, key, default)

    if is_integer(value) and value >= minimum and value <= maximum do
      {:ok, value}
    else
      :error
    end
  end

  defp temporary_directory(options) do
    directory = Keyword.get(options, :temporary_directory, System.tmp_dir())

    if is_binary(directory) and File.dir?(directory) do
      {:ok, Path.expand(directory)}
    else
      :error
    end
  end

  defp executable_option(options) do
    case Keyword.get(options, :executable) do
      nil -> {:ok, nil}
      executable when is_binary(executable) -> {:ok, executable}
      _other -> :error
    end
  end

  defp validate_input(pdf_data, maximum) do
    if byte_size(pdf_data) <= maximum do
      :ok
    else
      {:error, {:input_too_large, byte_size(pdf_data), maximum}}
    end
  end

  defp resolve_executable(nil) do
    case System.find_executable("magick") || System.find_executable("convert") do
      nil -> {:error, :executable_not_found}
      executable -> {:ok, executable}
    end
  end

  defp resolve_executable(executable) do
    expanded = Path.expand(executable)

    case File.stat(expanded) do
      {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 ->
        {:ok, expanded}

      _error ->
        {:error, :executable_not_found}
    end
  end

  defp create_workspace(root, attempts \\ @workspace_attempts)

  defp create_workspace(_root, 0) do
    {:error, {:workspace_unavailable, :eexist}}
  end

  defp create_workspace(root, attempts) do
    suffix = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    workspace = Path.join(root, "aludel-pdf-#{suffix}")

    case File.mkdir(workspace) do
      :ok -> secure_workspace(workspace)
      {:error, :eexist} -> create_workspace(root, attempts - 1)
      {:error, reason} -> {:error, {:workspace_unavailable, reason}}
    end
  end

  defp secure_workspace(workspace) do
    with :ok <- File.chmod(workspace, 0o700),
         {:ok, []} <- File.ls(workspace) do
      {:ok, workspace}
    else
      {:ok, _unexpected_entries} ->
        cleanup_workspace({:error, {:workspace_unavailable, :eexist}}, workspace)

      {:error, reason} ->
        cleanup_workspace({:error, {:workspace_unavailable, reason}}, workspace)
    end
  end

  defp convert_in_workspace(executable, pdf_data, settings, workspace) do
    outcome =
      try do
        {:result, run_conversion(executable, pdf_data, settings, workspace)}
      catch
        kind, _reason ->
          Logger.error("PDF conversion crashed (#{kind})")
          {:result, {:error, {:conversion_crashed, kind, :internal_error}}}
      end

    finalize_conversion(outcome, workspace)
  end

  defp run_conversion(executable, pdf_data, settings, workspace) do
    input_path = Path.join(workspace, "input.pdf")
    output_path = Path.join(workspace, "output.png")

    case write_private_input(input_path, pdf_data) do
      :ok ->
        case run_command(executable, input_path, output_path, settings, workspace) do
          {:completed, diagnostics, status} ->
            handle_command_result({diagnostics, status}, output_path, settings, workspace)

          :timeout_confirmed ->
            {:error, {:conversion_timeout, settings.timeout_ms}}

          {:propagate_exit, reason} ->
            {:propagate_exit, reason}

          :termination_unconfirmed ->
            Logger.error("PDF process-group termination could not be confirmed")
            {:preserve_workspace, {:error, :conversion_termination_unconfirmed}}
        end

      {:error, reason} ->
        {:error, {:conversion_io_failed, reason}}
    end
  end

  defp write_private_input(input_path, pdf_data) do
    case File.write(input_path, pdf_data, [:binary, :exclusive]) do
      :ok -> File.chmod(input_path, 0o600)
      error -> error
    end
  end

  defp run_command(executable, input_path, output_path, settings, workspace) do
    original_trap_exit = Process.flag(:trap_exit, true)

    try do
      command = [executable | command_arguments(input_path, output_path, settings)]

      options = [
        {:cd, workspace},
        {:env, [{"MAGICK_TEMPORARY_PATH", workspace}]},
        {:group, 0},
        {:kill_timeout, 0},
        :kill_group,
        :stdout,
        {:stderr, :stdout}
      ]

      case :exec.run_link(command, options) do
        {:ok, pid, os_pid} ->
          await_command(pid, os_pid, settings, original_trap_exit)

        {:error, _reason} ->
          raise "process-group runner failed"
      end
    after
      Process.flag(:trap_exit, original_trap_exit)
    end
  end

  defp await_command(pid, os_pid, settings, original_trap_exit) do
    timeout_token = make_ref()

    timer =
      Process.send_after(self(), {:pdf_conversion_timeout, timeout_token}, settings.timeout_ms)

    buffer = OutputBuffer.new(settings.max_diagnostic_bytes)

    await_command_message(pid, os_pid, timer, timeout_token, buffer, original_trap_exit)
  end

  defp await_command_message(pid, os_pid, timer, timeout_token, buffer, original_trap_exit) do
    receive do
      {:stdout, ^os_pid, data} ->
        await_command_message(
          pid,
          os_pid,
          timer,
          timeout_token,
          OutputBuffer.append(buffer, data),
          original_trap_exit
        )

      {:EXIT, ^pid, :normal} ->
        cancel_timeout(timer, timeout_token)
        {:completed, buffer.data, 0}

      {:EXIT, ^pid, {:exit_status, raw_status}} ->
        cancel_timeout(timer, timeout_token)
        {:completed, buffer.data, decode_exit_status(raw_status)}

      {:pdf_conversion_timeout, ^timeout_token} ->
        terminate_command(pid, os_pid, buffer)

      {:EXIT, _other_pid, :normal} when original_trap_exit == false ->
        await_command_message(pid, os_pid, timer, timeout_token, buffer, original_trap_exit)

      {:EXIT, _other_pid, reason} when original_trap_exit == false ->
        cancel_timeout(timer, timeout_token)
        terminate_for_exit(pid, os_pid, buffer, reason)
    end
  end

  defp terminate_command(pid, os_pid, buffer) do
    _stop_result = :exec.stop(pid)
    await_termination(pid, os_pid, buffer, :timeout_confirmed)
  end

  defp terminate_for_exit(pid, os_pid, buffer, reason) do
    _stop_result = :exec.stop(pid)
    await_termination(pid, os_pid, buffer, {:propagate_exit, reason})
  end

  defp await_termination(pid, os_pid, buffer, result) do
    receive do
      {:stdout, ^os_pid, data} ->
        await_termination(pid, os_pid, OutputBuffer.append(buffer, data), result)

      {:EXIT, ^pid, _reason} ->
        result
    after
      @termination_confirmation_ms ->
        :termination_unconfirmed
    end
  end

  defp cancel_timeout(timer, timeout_token) do
    Process.cancel_timer(timer, async: false, info: false)

    receive do
      {:pdf_conversion_timeout, ^timeout_token} -> :ok
    after
      0 -> :ok
    end
  end

  defp decode_exit_status(raw_status) do
    case :exec.status(raw_status) do
      {:status, status} -> status
      {:signal, signal, _core_dumped?} -> 128 + signal_number(signal)
    end
  end

  defp signal_number(signal) when is_integer(signal) do
    signal
  end

  defp signal_number(signal) do
    :exec.signal_to_int(signal)
  end

  defp command_arguments(input_path, output_path, settings) do
    timeout_seconds = div(settings.timeout_ms + 999, 1_000)

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
      Integer.to_string(timeout_seconds),
      "-density",
      Integer.to_string(settings.density),
      input_path <> "[0]",
      "-flatten",
      output_path
    ]
  end

  defp handle_command_result({_diagnostics, 0}, output_path, settings, _workspace) do
    read_output(output_path, settings.max_output_bytes)
  end

  defp handle_command_result({diagnostics, status}, _output_path, _settings, workspace)
       when is_integer(status) do
    Logger.warning("PDF conversion failed with exit status #{status}")
    {:error, {:conversion_failed, status, redact_workspace(diagnostics, workspace)}}
  end

  defp read_output(output_path, maximum) do
    case File.lstat(output_path) do
      {:ok, %{type: :regular, size: size}} when size <= maximum -> read_png(output_path, maximum)
      {:ok, %{type: :regular, size: size}} -> {:error, {:output_too_large, size, maximum}}
      {:ok, _stat} -> {:error, :output_missing}
      {:error, :enoent} -> {:error, :output_missing}
      {:error, reason} -> {:error, {:conversion_io_failed, reason}}
    end
  end

  defp read_png(output_path, maximum) do
    case File.open(output_path, [:read, :binary], &IO.binread(&1, maximum + 1)) do
      {:ok, image} when byte_size(image) > maximum ->
        {:error, {:output_too_large, byte_size(image), maximum}}

      {:ok, <<@png_signature, _rest::binary>> = image} ->
        {:ok, image}

      {:ok, _data} ->
        {:error, :invalid_output}

      {:error, reason} ->
        {:error, {:conversion_io_failed, reason}}
    end
  end

  defp redact_workspace(diagnostics, workspace) when is_binary(diagnostics) do
    String.replace(diagnostics, workspace, "[temporary directory]")
  end

  defp finalize_conversion({:result, {:propagate_exit, reason}}, workspace) do
    _cleanup_result = cleanup_workspace(:ok, workspace)
    exit(reason)
  end

  defp finalize_conversion({:result, {:preserve_workspace, result}}, _workspace) do
    result
  end

  defp finalize_conversion({:result, result}, workspace) do
    cleanup_workspace(result, workspace)
  end

  defp cleanup_workspace(result, workspace) do
    case File.rm_rf(workspace) do
      {:ok, _removed} -> result
      {:error, reason, _path} -> {:error, {:cleanup_failed, reason}}
    end
  end
end
